#!/usr/bin/env python3
"""Public certificate gating and isolated Certbot transaction/receipt tests. No live services."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('cert_fixture', ROOT / 'tests/lib/cert_fixture.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def main():
    with tempfile.TemporaryDirectory(prefix='certificate-tests-') as temp:
        work = Path(temp)
        ca = fixture.certificates(work / 'certs')
        scripts = fixture.prepare_copy(ROOT, work / 'source', ca)
        certs = work / 'certs'
        env = dict(os.environ)

        def run(command, expected=True, environment=None):
            result = subprocess.run(list(map(str, command)), env=environment or env,
                                    capture_output=True, timeout=30)
            # Never include raw stdout/stderr (or generated keys) in an assertion error.
            assert (result.returncode == 0) == expected, 'unexpected fixed-status result: ' + str(result.returncode)
            assert b'PRIVATE KEY' not in result.stdout + result.stderr
            return result

        def check(cert, key, expected=True, hostname='cdn.example.com', checker=None):
            return run([checker or scripts / 'check-public-cert.sh', '--cert', cert,
                        '--key', key, '--hostname', hostname], expected)

        check(certs / 'valid-fullchain.pem', certs / 'valid.key')
        check(certs / 'valid-fullchain.pem', certs / 'valid.key', False, 'wrong.example.com')
        check(certs / 'valid-fullchain.pem', certs / 'near-expiry.key', False)
        check(certs / 'near-expiry-fullchain.pem', certs / 'near-expiry.key', False)
        check(certs / 'expired-fullchain.pem', certs / 'expired.key', False)
        check(certs / 'valid.pem', certs / 'valid.key', False)  # Missing intermediate
        check(ca, certs / 'ca.key', False)
        # The real production checker must not trust this isolated CA.
        check(certs / 'valid-fullchain.pem', certs / 'valid.key', False,
              checker=ROOT / 'scripts/check-public-cert.sh')
        dummy = work / 'xray'
        dummy.write_text('#!/bin/sh\necho "unexpected-key-generation" >> "' + str(work / 'generated') + '"\nexit 1\n')
        dummy.chmod(0o700)
        run([scripts / 'prepare-node-files.sh', '--xray', dummy, '--work-dir', work / 'prepared',
             '--dest', 'example.com', '--cdn', 'cdn.example.com', '--address', '203.0.113.10'], False)
        assert not (work / 'prepared').exists() and not (work / 'generated').exists()
        run([ROOT / 'scripts/renew-selfsigned.sh'], False)
        print('[PASS] public trust, complete chain, hostname, key, expiry and no self-signed fallback')

        # Rewrite absolute paths and privilege checks only in disposable script COPIES.
        # The real hooks never accept a root-prefix or trust-store override.
        prefixes = ('/etc', '/opt', '/run', '/usr/local')

        def isolated(text):
            for prefix in prefixes:
                text = text.replace(prefix + '/', str(work) + prefix + '/')
            return text.replace('$EUID == 0', '1 == 1')

        for name in ('configure-certbot-renewal.sh', 'check-certbot-renewal.sh', 'deploy-certbot-cert.sh'):
            path = scripts / name
            path.write_text(isolated((ROOT / 'scripts' / name).read_text()))
            path.chmod(0o700)
        # Rewriting /etc also affects the fixture validator and the Nginx trust directive.
        checker = scripts / 'check-public-cert.sh'
        checker.write_text(isolated(checker.read_text()))
        templates = work / 'source/templates'
        templates.mkdir()
        (templates / 'certbot-deploy-hook').write_text(isolated((ROOT / 'templates/certbot-deploy-hook').read_text()))
        runtime = work / 'etc/xray-skill'
        origin = runtime / 'certs/origin'
        origin.mkdir(parents=True)
        (work / 'run').mkdir()
        lineage = work / 'etc/letsencrypt/live/test-cert'
        lineage.mkdir(parents=True)
        renewal = work / 'etc/letsencrypt/renewal'
        renewal.mkdir()
        (renewal / 'test-cert.conf').write_text('authenticator = webroot\n')
        (runtime / 'config.json').write_text(json.dumps({'inbounds': [
            {'tag': 'reality-in', 'streamSettings': {'security': 'reality', 'realitySettings': {}}},
            {'tag': 'xhttp-in', 'streamSettings': {'xhttpSettings': {'host': 'cdn.example.com'}}}]}))
        (runtime / 'recovery.json').write_text('{"certificate_mode":"self-signed","website":true}')
        (runtime / 'nginx.conf').write_text(isolated('proxy_ssl_trusted_certificate /etc/xray-skill/certs/origin/fullchain.pem;\n'))
        for source, target in [('valid-fullchain.pem', 'fullchain.pem'), ('valid.key', 'privkey.pem')]:
            shutil.copy2(certs / source, lineage / target)
        shutil.copy2(ca, origin / 'fullchain.pem')
        shutil.copy2(certs / 'ca.key', origin / 'privkey.pem')
        mock = work / 'mock'
        mock.mkdir()
        # Simulate only the external service manager, service-user command and Certbot network boundary.
        # Certificate parsing, trust validation, file replacement, rollback and receipt logic are real.
        mock_source = '''#!/usr/bin/env python3
import os, pathlib, subprocess, sys
w=pathlib.Path(os.environ['CERT_TEST_ROOT']); name=pathlib.Path(sys.argv[0]).name; args=sys.argv[1:]
if name=='install':
    cleaned=[];i=0
    while i<len(args):
        if args[i] in ('-o','-g'):i+=2
        else:cleaned.append(args[i]);i+=1
    sys.exit(subprocess.call(['/usr/bin/install',*cleaned]))
if name=='systemctl':
    with (w/'service-calls').open('a') as f:f.write(' '.join(args)+'\\n')
    if any('selfsigned' in a for a in args):sys.exit(1)
    if args[0]=='is-active' and (w/'inactive').exists() and any(a.endswith('.service') for a in args):sys.exit(3)
    if args[0]=='restart' and (w/'fail-restart-always').exists():sys.exit(1)
    if args[0] in ('restart','reload') and (w/('fail-'+args[0])).exists():
        (w/('fail-'+args[0])).unlink();sys.exit(1)
    sys.exit(0)
if name=='runuser':
    kind='nginx' if any('nginx' in a for a in args) else 'xray'
    sys.exit(int((w/('fail-'+kind+'-test')).exists()))
if name=='certbot':
    assert '--dry-run' in args and '--run-deploy-hooks' in args and '--cert-name' in args
    if (w/'fail-certbot').exists():sys.exit(1)
    if (w/'skip-hook').exists():sys.exit(0)
    os.environ['RENEWED_LINEAGE']=str(w/'etc/letsencrypt/live/test-cert')
    sys.exit(subprocess.call([str(w/'etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh')]))
raise SystemExit(1)
'''
        for name in ('install', 'systemctl', 'runuser', 'certbot'):
            path = mock / name
            path.write_text(mock_source)
            path.chmod(0o700)
        env.update(PATH=str(mock) + ':' + env['PATH'], CERT_TEST_ROOT=str(work))
        run([scripts / 'configure-certbot-renewal.sh', '--lineage', lineage])
        assert (origin / 'fullchain.pem').read_bytes() == (lineage / 'fullchain.pem').read_bytes()
        assert json.loads((runtime / 'recovery.json').read_text())['certificate_mode'] == 'provided'
        assert (origin / 'privkey.pem').stat().st_mode & 0o777 == 0o640
        assert (runtime / 'certbot.json').stat().st_mode & 0o777 == 0o600
        assert '/ssl/certs/ca-certificates.crt' in (runtime / 'nginx.conf').read_text()
        run([scripts / 'check-certbot-renewal.sh'], False)  # Timer alone is not enough.
        run([scripts / 'check-certbot-renewal.sh', '--dry-run'])
        run([scripts / 'check-certbot-renewal.sh'])
        print('[PASS] legacy certificate migration, private permissions, renewal hook and dry-run receipt')

        tracked = [origin / 'fullchain.pem', origin / 'privkey.pem', runtime / 'recovery.json',
                   runtime / 'nginx.conf', runtime / 'certbot-deploy-receipt.json', runtime / 'config.json']
        before = [p.read_bytes() for p in tracked]
        hook_env = dict(env, RENEWED_LINEAGE=str(lineage))
        for fail in ('xray-test', 'nginx-test', 'restart', 'reload'):
            (work / ('fail-' + fail)).touch()
            run([scripts / 'deploy-certbot-cert.sh'], False, hook_env)
            (work / ('fail-' + fail)).unlink(missing_ok=True)
            assert [p.read_bytes() for p in tracked] == before
        run([scripts / 'deploy-certbot-cert.sh'], environment=dict(env, RENEWED_LINEAGE='/unrelated'))
        assert [p.read_bytes() for p in tracked] == before
        shutil.copy2(ca, lineage / 'fullchain.pem')
        run([scripts / 'deploy-certbot-cert.sh'], False, hook_env)
        assert [p.read_bytes() for p in tracked] == before
        shutil.copy2(certs / 'valid-fullchain.pem', lineage / 'fullchain.pem')
        print('[PASS] validation/restart/reload failures roll back; invalid and unrelated lineages never replace runtime')
        (work / 'inactive').touch()
        (work / 'service-calls').write_text('')
        run([scripts / 'deploy-certbot-cert.sh'], environment=hook_env)
        calls = (work / 'service-calls').read_text()
        assert 'restart ' not in calls and 'reload ' not in calls
        (work / 'inactive').unlink()
        print('[PASS] deliberately stopped services remain stopped after certificate deployment')
        (work / 'fail-restart-always').touch()
        result = run([scripts / 'deploy-certbot-cert.sh'], False, hook_env)
        assert b'rollback_ok=false' in result.stderr
        backups = list((runtime / 'certs').glob('.deploy.*'))
        assert backups and all(p.stat().st_mode & 0o777 == 0o700 for p in backups)
        assert (backups[0] / 'old.key').exists()
        (work / 'fail-restart-always').unlink()
        print('[PASS] failed service recovery retains private certificate backups')
        for fail in ('skip-hook', 'fail-certbot'):
            (work / fail).touch()
            run([scripts / 'check-certbot-renewal.sh', '--dry-run'], False)
            assert not (runtime / 'certbot-renewal-verified.json').exists()
            (work / fail).unlink()
        run([scripts / 'check-certbot-renewal.sh', '--dry-run'])
        (renewal / 'test-cert.conf').write_text('changed configuration\n')
        run([scripts / 'check-certbot-renewal.sh'], False)
        print('[PASS] Certbot exit zero without a deploy hook, failed renewal and stale evidence cannot pass')


if __name__ == '__main__':
    os.umask(0o077)
    main()

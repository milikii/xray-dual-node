#!/usr/bin/env python3
"""Loopback-only website, REALITY, XHTTP packet-up and source-control integration test."""
import argparse
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import traceback


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xray', required=True)
    parser.add_argument('--base-port', type=int, default=28540)
    args = parser.parse_args()
    xray = str(Path(args.xray).resolve())
    nginx = shutil.which('nginx')
    if not nginx and os.access('/usr/sbin/nginx', os.X_OK):
        nginx = '/usr/sbin/nginx'
    if not nginx:
        print('[FAIL] P01: Nginx executable missing; check package installation and /usr/sbin')
        raise SystemExit(2)
    if not 1024 <= args.base_port < 65525:
        print('[FAIL] P02: base port must be between 1024 and 65524')
        raise SystemExit(2)
    if not os.access(xray, os.X_OK):
        print('[FAIL] P03: verified Xray binary is not executable by the current user')
        raise SystemExit(2)
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('web', root / 'scripts/prepare-website.py')
    web = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(web)
    front, router, backend, frontend, cam, socks_a, socks_b, echo = range(args.base_port, args.base_port + 8)
    for port in range(args.base_port, args.base_port + 8):
        with socket.socket() as probe:
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            probe.bind(('127.0.0.1', port))
    with tempfile.TemporaryDirectory(prefix='xray-website-') as temp:
        work = Path(temp)
        processes = []
        service = None
        log = open(work / 'private.log', 'wb')
        def run(command, **kwargs):
            try:
                return subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=log, timeout=30, **kwargs).stdout
            except subprocess.CalledProcessError as error:
                log.flush()
                data = (work / 'private.log').read_text(errors='replace')
                categories = ['unknown authority', 'connection refused', 'timeout', 'rejected', 'EOF',
                    'authentication failed or validation criteria not met',
                    'target sent incorrect server hello or handshake incomplete',
                    'handshake did not complete successfully', 'received real certificate', 'unsupported TLS version']
                flags = [label for label in categories if label in data]
                print(f'[FAIL] child exit={error.returncode}; received_bytes={len(error.stdout or b"")}; diagnostic categories={flags}', flush=True)
                raise
        def write(name, value):
            path = work / name
            path.write_text(json.dumps(value))
            path.chmod(0o600)
            return str(path)
        def start(command, port):
            process = subprocess.Popen(command, stdout=log, stderr=log)
            processes.append(process)
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError('process exited')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1):
                        return
                except OSError:
                    time.sleep(.05)
            raise RuntimeError('listener timeout')
        try:
            assert run([xray, 'version']).startswith(b'Xray 26.9.30 ')
            keys = dict(line.split(': ', 1) for line in run([xray, 'x25519']).decode().splitlines() if ': ' in line)
            public = keys.get('Password (PublicKey)', keys.get('Password', keys.get('PublicKey')))
            uuid = run([xray, 'uuid']).decode().strip()
            encryption_output = run([xray, 'vlessenc']).decode()
            encryption = re.search(r'"encryption": "(mlkem768x25519plus\.[^"]+)"', encryption_output)[1]
            decryption = re.search(r'"decryption": "(mlkem768x25519plus\.[^"]+)"', encryption_output)[1]
            cert, key = str(work / 'cert.pem'), str(work / 'key.pem')
            run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
                 '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=cdn.example.com',
                 '-addext', 'subjectAltName=DNS:cdn.example.com,DNS:example.com,IP:127.0.0.1'])
            tls = {'alpn': ['h2', 'http/1.1'], 'certificates': [{'certificateFile': cert, 'keyFile': key}]}
            server = {'log': {'loglevel': 'warning'}, 'inbounds': [
                {'tag': 'reality-in', 'listen': '127.0.0.1', 'port': front, 'protocol': 'vless',
                 'settings': {'clients': [{'id': uuid, 'flow': 'xtls-rprx-vision'}], 'decryption': 'none'},
                 'streamSettings': {'network': 'raw', 'security': 'reality', 'realitySettings': {
                     'target': f'127.0.0.1:{router}', 'xver': 2, 'serverNames': ['example.com'],
                     'privateKey': keys['PrivateKey'], 'shortIds': ['12345678']}}},
                {'tag': 'sni-router', 'listen': '127.0.0.1', 'port': router, 'protocol': 'tunnel',
                 'settings': {'address': '127.0.0.1', 'port': 9, 'network': 'tcp'},
                 'streamSettings': {'sockopt': {'acceptProxyProtocol': True}},
                 'sniffing': {'enabled': True, 'destOverride': ['tls'], 'routeOnly': True}},
                {'tag': 'xhttp-in', 'listen': '127.0.0.1', 'port': backend, 'protocol': 'vless',
                 'settings': {'clients': [{'id': uuid}], 'decryption': decryption},
                 'streamSettings': {'network': 'xhttp', 'security': 'tls', 'tlsSettings': tls,
                     'xhttpSettings': {'host': 'cdn.example.com', 'path': '/test-path', 'mode': 'packet-up'},
                     'sockopt': {'acceptProxyProtocol': False}}}],
                # v26.9.30 blocks private VLESS targets by default. Permit only this local fixture.
                'outbounds': [{'tag': 'direct', 'protocol': 'freedom', 'settings': {'finalRules': [
                    {'action': 'allow', 'network': 'tcp', 'ip': ['127.0.0.1'], 'port': echo}]}},
                    {'tag': 'deny', 'protocol': 'blackhole'},
                    {'tag': 'web', 'protocol': 'freedom', 'settings': {'redirect': f'127.0.0.1:{frontend}', 'proxyProtocol': 2}},
                    {'tag': 'cam', 'protocol': 'freedom', 'settings': {'redirect': f'127.0.0.1:{cam}'}}],
                'routing': {'rules': [
                    {'inboundTag': ['sni-router'], 'domain': ['full:cdn.example.com'], 'source': ['127.0.0.1/32'], 'outboundTag': 'web'},
                    {'inboundTag': ['sni-router'], 'domain': ['full:example.com'], 'outboundTag': 'cam'},
                    {'inboundTag': ['sni-router'], 'outboundTag': 'deny'}]}}
            site_root = work / 'public'
            initial = site_root / 'releases' / 'initial'
            initial.parent.mkdir(parents=True)
            metadata = web.create_site(initial, seed=123)
            site = site_root / 'current'
            site.symlink_to(Path('releases') / 'initial')
            runtime = work / 'run'
            runtime.mkdir()
            config = web.nginx_config(server, str(site), cert, key, str(runtime), frontend)
            if os.geteuid() == 0:
                # The real unit runs as a dedicated non-root user; keep synthetic files private here.
                config = 'user root;\n' + config
            # A separate local TLS fixture supplies REALITY's camouflage target.
            position = config.rfind('}')
            config = config[:position] + f'''server {{ listen 127.0.0.1:{cam} ssl http2;
                server_name example.com; ssl_certificate {cert}; ssl_certificate_key {key};
                ssl_protocols TLSv1.3; ssl_ecdh_curve X25519;
                root {site}; }}\n''' + config[position:]
            nginx_config = work / 'nginx.conf'
            nginx_config.write_text(config)
            run([nginx, '-t', '-q', '-c', str(nginx_config)])
            server_file = write('server.json', server)
            run([xray, 'run', '-test', '-c', server_file])
            start([xray, 'run', '-c', server_file], front)
            start([nginx, '-c', str(nginx_config), '-g', 'daemon off;'], frontend)
            curl = ['curl', '--noproxy', '*', '-sS', '--max-time', '8', '--cacert', cert,
                    '--resolve', f'cdn.example.com:{front}:127.0.0.1']
            url = f'https://cdn.example.com:{front}'
            assert run(curl + [url + '/']) == (site / 'index.html').read_bytes()
            assert run(curl + [url + '/archive.html']) == (site / 'archive.html').read_bytes()
            assert run(curl + ['-o', '/dev/null', '-w', '%{http_code}', url + '/missing']) == b'404'
            assert run(curl + ['-o', '/dev/null', '-w', '%{http_code}', url + '/.git/config']) == b'404'
            original_page = (site / 'index.html').read_bytes()
            original_style = (site / 'style.css').read_bytes()
            news_state = work / 'news-state'
            news_state.mkdir()
            (news_state / 'config.json').write_text(json.dumps(metadata))
            def public_feed(source_id, previous):
                source = web.news.SOURCES[source_id]
                return {'items': [{'title': 'Synthetic AI update', 'summary': 'Public-source test excerpt.',
                    'url': 'https://' + source['hosts'][0] + '/sample', 'date': '2026-10-05T10:00:00+00:00',
                    'source': source_id, 'category': source['category']}]}
            assert web.news.refresh(site_root, news_state, public_feed)['published']
            assert (site / 'index.html').read_bytes() != original_page
            assert (site / 'style.css').read_bytes() == original_style
            assert run(curl + [url + '/']) == (site / 'index.html').read_bytes()
            print('[PASS] atomic feed refresh served immediately without changing style or restarting services', flush=True)
            for source, domain in [('127.0.0.2', 'cdn.example.com'), ('127.0.0.1', 'unknown.example.com')]:
                denied = subprocess.run(['curl', '--noproxy', '*', '-sS', '--max-time', '3', '--interface', source,
                    '--cacert', cert, '--resolve', f'{domain}:{front}:127.0.0.1', f'https://{domain}:{front}/'],
                    stdout=subprocess.PIPE, stderr=log)
                assert denied.returncode != 0
            assert run(['curl', '--noproxy', '*', '-sS', '--max-time', '5', '--cacert', cert,
                        '--resolve', f'example.com:{front}:127.0.0.1', f'https://example.com:{front}/']) == (site / 'index.html').read_bytes()
            print('[PASS] website pages/404, TLS verification, source/SNI denial and camouflage relay', flush=True)
            payload = b'packet-up-streaming-test\n' * 100000
            class Echo(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                def do_POST(self):
                    body = self.rfile.read(int(self.headers['Content-Length']))
                    reply = hashlib.sha256(body).hexdigest().encode()
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(reply)))
                    self.end_headers()
                    self.wfile.write(reply)
                def log_message(self, *args):
                    pass
            service = http.server.ThreadingHTTPServer(('127.0.0.1', echo), Echo)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(cert, key)
            service.socket = context.wrap_socket(service.socket, server_side=True)
            threading.Thread(target=service.serve_forever, daemon=True).start()
            upload = work / 'upload'
            upload.write_bytes(payload)
            # Keep the packet-up server and HTTP/1.1 Nginx upstream unchanged while
            # varying one client setting at a time, including the previous default.
            cases = [('a', socks_a, None, None),
                     ('b', socks_b, 'packet-up', ['h2', 'http/1.1']),
                     ('b', socks_b, 'packet-up', ['h2']),
                     ('b', socks_b, 'auto', ['h2'])]
            for node, port, mode, alpn in cases:
                stream = {'network': 'raw', 'security': 'reality', 'realitySettings': {
                    'serverName': 'example.com', 'fingerprint': 'chrome', 'password': public, 'shortId': '12345678'}} if node == 'a' else {
                    'network': 'xhttp', 'security': 'tls', 'xhttpSettings': {
                        'host': 'cdn.example.com', 'path': '/test-path', 'mode': mode},
                    'tlsSettings': {'serverName': 'cdn.example.com', 'fingerprint': 'chrome', 'alpn': alpn,
                        'certificates': [{'certificateFile': cert, 'usage': 'verify'}]}}
                user = {'id': uuid, 'encryption': 'none', 'flow': 'xtls-rprx-vision'} if node == 'a' else {'id': uuid, 'encryption': encryption}
                client = {'log': {'loglevel': 'warning'}, 'inbounds': [{'listen': '127.0.0.1', 'port': port,
                    'protocol': 'socks', 'settings': {}}], 'outbounds': [{'protocol': 'vless', 'settings': {
                        'vnext': [{'address': '127.0.0.1', 'port': front, 'users': [user]}]}, 'streamSettings': stream}]}
                client_file = write(f'client-{node}.json', client)
                run([xray, 'run', '-test', '-c', client_file])
                start([xray, 'run', '-c', client_file], port)
                proxy = ['curl', '-sS', '--max-time', '15', '--cacert', cert, '--noproxy', '', '--socks5-hostname', f'127.0.0.1:{port}']
                target = f'https://127.0.0.1:{echo}/'
                assert run(proxy + [target]) == payload
                assert run(proxy + ['--data-binary', '@' + str(upload), target]) == hashlib.sha256(payload).hexdigest().encode()
                label = node.upper() if node == 'a' else f'B mode={mode} alpn={",".join(alpn)} extra=absent'
                print(f'[PASS] authenticated node {label} multi-megabyte download/upload', flush=True)
                processes[-1].terminate()
                processes[-1].wait(timeout=5)
                client['outbounds'][0]['settings']['vnext'][0]['users'][0]['id'] = '00000000-0000-0000-0000-000000000000'
                wrong = write(f'wrong-{node}.json', client)
                start([xray, 'run', '-c', wrong], port)
                rejected = subprocess.run(proxy + ['--max-time', '3', target], stdout=subprocess.PIPE, stderr=log)
                assert rejected.returncode != 0
                processes[-1].terminate()
                processes[-1].wait(timeout=5)
                print(f'[PASS] wrong credential rejected for node {label}', flush=True)
            # The proxy must surface backend failure, never replace it with the static homepage.
            processes[0].terminate()
            processes[0].wait(timeout=5)
            raw = socket.create_connection(('127.0.0.1', frontend), timeout=5)
            raw.sendall(f'PROXY TCP4 127.0.0.1 127.0.0.1 12345 {frontend}\r\n'.encode())
            context = ssl.create_default_context(cafile=cert)
            with context.wrap_socket(raw, server_hostname='cdn.example.com') as peer:
                peer.sendall(b'GET /test-path/session HTTP/1.1\r\nHost: cdn.example.com\r\nConnection: close\r\n\r\n')
                response = b''
                while chunk := peer.recv(65536):
                    response += chunk
            assert response.startswith(b'HTTP/1.1 502') and (site / 'index.html').read_bytes() not in response
            bad_tls = (work / 'invalid-trust.pem')
            bad_tls.write_text('invalid certificate')
            invalid = config.replace(f'proxy_ssl_trusted_certificate {cert};', f'proxy_ssl_trusted_certificate {bad_tls};')
            invalid_config = work / 'bad-nginx.conf'
            invalid_config.write_text(invalid)
            assert subprocess.run([nginx, '-t', '-q', '-c', str(invalid_config)], stdout=log, stderr=log).returncode != 0
            print('[PASS] backend failure stays 502; invalid upstream trust rejected', flush=True)
            # Exercise the real preparation entrypoint, with CF downloads replaced by public test CIDRs.
            mock_bin = work / 'mock-bin'
            mock_bin.mkdir()
            mock_curl = mock_bin / 'curl'
            mock_curl.write_text('#!/bin/sh\ncase "$*" in\n*ips-v4*) printf "1.1.1.0/24\\n8.8.8.0/24\\n9.9.9.0/24\\n11.0.0.0/8\\n12.0.0.0/8\\n13.0.0.0/8\\n14.0.0.0/8\\n15.0.0.0/8\\n16.0.0.0/8\\n17.0.0.0/8\\n18.0.0.0/8\\n";;\n*ips-v6*) printf "2001:db8::/32\\n";;\n*) exit 1;;\nesac\n')
            mock_curl.chmod(0o700)
            fixture_spec = importlib.util.spec_from_file_location('cert_fixture', root / 'tests/lib/cert_fixture.py')
            fixture = importlib.util.module_from_spec(fixture_spec)
            fixture_spec.loader.exec_module(fixture)
            prep_certs = work / 'prep-certs'
            prep_ca = fixture.certificates(prep_certs)
            prep_scripts = fixture.prepare_copy(root, work / 'prep-source', prep_ca)
            certificate_args = ['--origin-cert', str(prep_certs / 'valid-fullchain.pem'),
                                '--origin-key', str(prep_certs / 'valid.key')]
            prepared = work / 'prepared'
            environment = dict(os.environ, PATH=str(mock_bin) + os.pathsep + os.environ['PATH'])
            run([str(prep_scripts / 'prepare-node-files.sh'), '--xray', xray, '--work-dir', str(prepared),
                 '--dest', 'example.com', '--cdn', 'cdn.example.com', '--address', '203.0.113.10', '--mldsa', 'off',
                 '--website-fetch', 'off', *certificate_args], env=environment)
            rendered = json.loads((prepared / 'server.json').read_text())
            target = next(item for item in rendered['outbounds'] if item['tag'] == 'to-node-b')
            backend_config = next(item for item in rendered['inbounds'] if item['tag'] == 'xhttp-in')
            assert target['settings'] == {'redirect': '127.0.0.1:8003', 'proxyProtocol': 2}
            assert backend_config['streamSettings']['sockopt']['acceptProxyProtocol'] is False
            assert backend_config['streamSettings']['security'] == 'tls'
            assert json.loads((prepared / 'prepared.json').read_text())['website'] is True
            client_b = json.loads((prepared / 'client-b.json').read_text())['outbounds'][0]
            assert client_b['streamSettings']['tlsSettings'] == {
                'serverName': 'cdn.example.com', 'fingerprint': 'chrome', 'alpn': ['h2']}
            assert client_b['streamSettings']['xhttpSettings']['mode'] == 'auto'
            assert 'extra' not in client_b['streamSettings']['xhttpSettings']
            assert client_b['settings']['vnext'][0]['users'][0]['encryption'].startswith('mlkem768x25519plus.')
            content = ''.join(file.read_text() for file in (prepared / 'website/site').iterdir())
            for value in [backend_config['streamSettings']['xhttpSettings']['path'],
                          backend_config['settings']['clients'][0]['id'], backend_config['settings']['decryption']]:
                assert value not in content
            print('[PASS] actual node preparation produces website topology without public credentials', flush=True)
            legacy = work / 'without-website'
            run([str(prep_scripts / 'prepare-node-files.sh'), '--xray', xray, '--work-dir', str(legacy),
                 '--dest', 'example.com', '--cdn', 'cdn.example.com', '--address', '203.0.113.10',
                 '--mldsa', 'off', '--website', 'off', *certificate_args], env=environment)
            legacy_config = json.loads((legacy / 'server.json').read_text())
            legacy_target = next(item for item in legacy_config['outbounds'] if item['tag'] == 'to-node-b')
            assert legacy_target['settings']['redirect'] == '127.0.0.1:8002'
            assert not (legacy / 'website').exists()
            legacy_b = json.loads((legacy / 'client-b.json').read_text())['outbounds'][0]
            assert legacy_b['streamSettings']['tlsSettings'] == client_b['streamSettings']['tlsSettings']
            assert legacy_b['streamSettings']['xhttpSettings']['mode'] == 'auto'
            assert 'extra' not in legacy_b['streamSettings']['xhttpSettings']
            print('[PASS] website-off preparation retains original direct XHTTP topology', flush=True)
            print('[PASS] generated B clients use auto/h2 without ECH/Extra; ML-KEM and packet-up server retained', flush=True)
            print('LOCAL_WEBSITE: PASS (real Cloudflare, user-network connectivity and systemd lifecycle still require verification)', flush=True)
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if service:
                service.shutdown()
                service.server_close()
            log.close()


if __name__ == '__main__':
    os.umask(0o077)
    try:
        main()
    except Exception:
        import sys
        frames = traceback.extract_tb(sys.exc_info()[2])
        local = [frame.lineno for frame in frames if frame.filename == __file__]
        print(f'[FAIL] local website integration at lines {local}; private artifacts withheld')
        raise SystemExit(1)

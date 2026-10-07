#!/usr/bin/env python3
"""Run the HTTP-01 Nginx template on loopback, without systemd or privileged ports."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def main():
    nginx = shutil.which('nginx') or '/usr/sbin/nginx'
    with tempfile.TemporaryDirectory(prefix='acme-http-test-') as temp:
        work = Path(temp)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        webroot = work / 'webroot'
        challenges = webroot / '.well-known/acme-challenge'
        challenges.mkdir(parents=True)
        (challenges / 'synthetic-token_123').write_text('synthetic-proof')
        (webroot / 'private.txt').write_text('must-not-be-served')
        runtime = work / 'run'
        runtime.mkdir()
        config = (ROOT / 'templates/acme-nginx.conf').read_text()
        config = config.replace('listen 80;', f'listen 127.0.0.1:{port};').replace('listen [::]:80;', '')
        config = config.replace('/run/xray-skill-acme', str(runtime)).replace('/var/lib/xray-skill-acme', str(webroot))
        if os.geteuid() == 0:
            config = 'user root;\n' + config
        path = work / 'nginx.conf'
        path.write_text(config)
        result = subprocess.run([nginx, '-t', '-q', '-c', str(path)], capture_output=True, timeout=10)
        assert result.returncode == 0, 'isolated HTTP challenge config failed'
        with open(work / 'private.log', 'wb') as log:
            process = subprocess.Popen([nginx, '-c', str(path), '-g', 'daemon off;'], stdout=log, stderr=log)
            try:
                for _ in range(100):
                    assert process.poll() is None, 'isolated HTTP challenge service exited'
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=.1):
                            break
                    except OSError:
                        time.sleep(.05)
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                base = f'http://127.0.0.1:{port}'
                with opener.open(base + '/.well-known/acme-challenge/synthetic-token_123', timeout=5) as response:
                    assert response.status == 200 and response.read() == b'synthetic-proof'
                for suffix in ('/', '/private.txt', '/.well-known/acme-challenge/missing',
                               '/.well-known/acme-challenge/../../private.txt'):
                    try:
                        opener.open(base + suffix, timeout=5)
                    except urllib.error.HTTPError as error:
                        assert error.code == 404
                    else:
                        raise AssertionError('non-challenge content exposed')
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    print('[PASS] persistent HTTP-01 template serves challenge proof only; other paths return 404')


if __name__ == '__main__':
    os.umask(0o077)
    main()

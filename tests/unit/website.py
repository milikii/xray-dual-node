#!/usr/bin/env python3
"""Static website generation: all themes, valid links, no private fields, stable output."""
import importlib.util
from pathlib import Path
import tempfile
import re
import unittest
import os
import shutil
import subprocess

spec = importlib.util.spec_from_file_location('website', Path(__file__).resolve().parents[2] / 'scripts/prepare-website.py')
web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web)


class WebsiteTests(unittest.TestCase):
    def test_nginx_config_works_as_unprivileged_user(self):
        nginx = shutil.which('nginx') or '/usr/sbin/nginx'
        if not os.access(nginx, os.X_OK) or not shutil.which('openssl'):
            self.skipTest('nginx and openssl required')
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            work.chmod(0o755)
            runtime = work / 'run'
            runtime.mkdir()
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                '-subj', '/CN=cdn.example.com', '-days', '1', '-keyout', str(work / 'key'),
                '-out', str(work / 'cert')], check=True, capture_output=True)
            # Synthetic test key only; allow the isolated unprivileged nginx to read it.
            (work / 'key').chmod(0o644)
            server = {'inbounds': [{'tag': 'xhttp-in', 'listen': '127.0.0.1', 'port': 8002,
                'streamSettings': {'xhttpSettings': {'host': 'cdn.example.com', 'path': '/fixture'}}}]}
            config = work / 'nginx.conf'
            config.write_text(web.nginx_config(server, str(work), str(work / 'cert'),
                str(work / 'key'), str(runtime)))
            options = {}
            if os.geteuid() == 0:
                os.chown(runtime, 65534, 65534)
                options = {'user': 65534, 'group': 65534, 'extra_groups': []}
            result = subprocess.run([nginx, '-t', '-q', '-c', str(config)],
                capture_output=True, text=True, **options)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_themes_have_working_local_links_and_no_external_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            for theme in web.THEMES:
                site = Path(tmp) / theme
                web.create_site(site, theme, seed=123)
                self.assertEqual(site.stat().st_mode & 0o777, 0o755)
                for file in site.glob('*.html'):
                    text = file.read_text()
                    self.assertNotIn('<img', text)
                    self.assertNotIn('<script', text)
                    for ref in re.findall(r'(?:href|src)="([^"]+)"', text):
                        if ref.startswith('https://'):
                            continue
                        self.assertTrue((site / (ref.lstrip('/') or 'index.html')).is_file())
                    self.assertEqual(file.stat().st_mode & 0o777, 0o644)

    def test_seed_reproduces_and_random_choices_vary(self):
        with tempfile.TemporaryDirectory() as tmp:
            variants = set()
            for seed in range(20):
                a, b = Path(tmp) / f'a{seed}', Path(tmp) / f'b{seed}'
                web.create_site(a, seed=seed)
                web.create_site(b, seed=seed)
                self.assertEqual((a / 'index.html').read_bytes(), (b / 'index.html').read_bytes())
                variants.add((a / 'index.html').read_text() + (a / 'style.css').read_text())
            self.assertGreater(len(variants), 15)

    def test_config_inputs_cannot_inject_nginx_directives(self):
        for host, path in [('cdn.example.com;include x', '/abc'), ('cdn.example.com', '/x;return 200;')]:
            server = {'inbounds': [{'tag': 'xhttp-in', 'listen': '127.0.0.1', 'port': 8002,
                'streamSettings': {'xhttpSettings': {'host': host, 'path': path}}}]}
            with self.assertRaises(ValueError):
                web.nginx_config(server, '/tmp/site', '/tmp/cert', '/tmp/key', '/tmp/run')


if __name__ == '__main__':
    unittest.main()

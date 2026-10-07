#!/usr/bin/env python3
"""Exercise the rule CLI without exposing private node fields, including on failure."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/show-cf-cache-rule.py'


class CacheRuleTests(unittest.TestCase):
    def config(self, host='CDN.Example.COM'):
        return {'privateKey': 'synthetic-private-key', 'inbounds': [{
            'tag': 'xhttp-in', 'settings': {'clients': [{'id': 'synthetic-user-id'}]},
            'streamSettings': {'network': 'xhttp', 'security': 'tls',
                               'xhttpSettings': {'host': host, 'path': '/synthetic-secret-path'}}}]}

    def invoke(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'private.json'
            content = data if isinstance(data, str) else json.dumps(data)
            path.write_text(content)
            path.chmod(0o600)
            result = subprocess.run([sys.executable, str(SCRIPT), '--server-config', str(path)],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(path.read_text(), content)
        for secret in ('synthetic-private-key', 'synthetic-user-id', 'synthetic-secret-path'):
            self.assertNotIn(secret, result.stdout + result.stderr)
        return result

    def test_hostname_only(self):
        result = self.invoke(self.config())
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '(http.host eq "cdn.example.com")\n')
        self.assertEqual(result.stderr, '')

    def test_invalid_host_cannot_inject_expression_or_leak_config(self):
        for host in ('cdn.example.com") or true or ("', 'cdn.example.com\n', 'https://cdn.example.com',
                     '*.example.com', '203.0.113.10', 'localhost', '-bad.example.com',
                     'cdn..example.com', 'synthetic-secret-path', None, ['cdn.example.com']):
            with self.subTest(host_type=type(host).__name__):
                result = self.invoke(self.config(host))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertEqual(result.stderr, '[FAIL] CF_CACHE: cannot validate XHTTP hostname; private details withheld\n')

    def test_malformed_or_ambiguous_config_fails_privately(self):
        duplicate = self.config()
        duplicate['inbounds'].append(copy.deepcopy(duplicate['inbounds'][0]))
        wrong_transport = self.config()
        wrong_transport['inbounds'][0]['streamSettings']['network'] = 'ws'
        for config in ('{"synthetic-private-key":', {}, {'inbounds': [None]}, duplicate, wrong_transport):
            result = self.invoke(config)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    unittest.main()

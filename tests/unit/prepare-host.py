#!/usr/bin/env python3
"""Exercise host bootstrap with isolated paths and fake package commands."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class HostTests(unittest.TestCase):
    def run_fixture(self, *, installed=False, apt_failure=False, policy=None):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            bindir = work / 'bin'
            bindir.mkdir()
            policy_path = work / 'policy-rc.d'
            if policy is not None:
                policy_path.write_text(policy)
                policy_path.chmod(0o755)
            (work / 'os-release').write_text('ID=debian\nVERSION_ID=13\n')
            source = (ROOT / 'scripts/prepare-host.sh').read_text()
            source = source.replace('$EUID', '0')
            source = source.replace('/etc/os-release', str(work / 'os-release'))
            source = source.replace('/run/systemd/system', str(work))
            source = source.replace('/usr/sbin/policy-rc.d', str(policy_path))
            source = source.replace('/usr/sbin:/usr/bin:/sbin:/bin:$PATH', f'{bindir}:/usr/bin:/bin')
            script = work / 'prepare-host.sh'
            script.write_text(source)
            commands = {
                'uname': 'echo x86_64',
                'dpkg-query': "printf 'install ok installed'" if installed else 'exit 1',
                'systemctl': '[ "$1" != cat ]',
                'apt-get': '''"$TEST_POLICY" nginx start
[ "$?" = 101 ] || exit 90
echo "$*" >> "$TEST_APT_LOG"
exit "${TEST_APT_EXIT:-0}"''',
            }
            for name in ('python3', 'jq', 'curl', 'unzip', 'openssl', 'ss', 'zstd', 'flock', 'certbot', 'nginx'):
                commands[name] = 'exit 0'
            for name, content in commands.items():
                path = bindir / name
                path.write_text('#!/bin/sh\n' + content + '\n')
                path.chmod(0o755)
            log = work / 'apt.log'
            result = subprocess.run(['bash', str(script)], capture_output=True, text=True,
                env={**os.environ, 'TEST_POLICY': str(policy_path), 'TEST_APT_LOG': str(log),
                     'TEST_APT_EXIT': '42' if apt_failure else '0'})
            return result.returncode, log.read_text() if log.exists() else '', policy_path.read_text() if policy_path.exists() else None

    def test_missing_dependencies_installed_with_startup_suppressed(self):
        status, log, policy = self.run_fixture()
        self.assertEqual(status, 0)
        self.assertIn('update\n', log)
        self.assertIn('python3 certbot nginx', log)
        self.assertIsNone(policy)

    def test_apt_failure_stops_and_removes_temporary_policy(self):
        status, log, policy = self.run_fixture(apt_failure=True)
        self.assertNotEqual(status, 0)
        self.assertEqual(log, 'update\n')
        self.assertIsNone(policy)

    def test_existing_policy_preserved(self):
        for code in (0, 101):
            original = f'#!/bin/sh\nexit {code}\n'
            status, log, policy = self.run_fixture(policy=original)
            self.assertEqual(policy, original)
            self.assertEqual(status == 0, code == 101)
            self.assertEqual(bool(log), code == 101)

    def test_repeat_with_all_packages_present_does_not_call_apt(self):
        self.assertEqual(self.run_fixture(installed=True), (0, '', None))


if __name__ == '__main__':
    unittest.main()

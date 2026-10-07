#!/usr/bin/env python3
"""Run the real auth harness against disposable command fakes, including failed baselines."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FAKE = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
work=Path(os.environ['AUTH_TEST_WORK'])
scenario=os.environ['AUTH_TEST_SCENARIO']
command=Path(sys.argv[0]).name
if command=='ss':
 if (work/'active-path').exists():print('LISTEN 0 128 127.0.0.1:20810')
elif command=='xray':
 if sys.argv[1]=='run':
  config=Path(sys.argv[sys.argv.index('-c')+1])
  if '-test' in sys.argv:
   if scenario=='config-failure':
    print('SECRET_SENTINEL',file=sys.stderr);sys.exit(1)
   (work/'active-path').write_text(str(config))
  else:os.execv('/bin/sleep',['sleep','60'])
 elif sys.argv[1]=='mldsa65':print('Verify: NEWVERIFY')
 elif sys.argv[1]=='vlessenc':print('Authentication: ML-KEM-768, Post-Quantum\\n"encryption": "mlkem768x25519plus.NEW"')
elif command=='curl':
 config=json.loads(Path((work/'active-path').read_text()).read_text())
 node=config['outbounds'][0]
 tag=node['tag']
 if (scenario=='fail-b' and tag=='node-b') or (scenario=='fail-a' and tag=='node-a'):
  Path(config['log']['error']).write_text('unexpected status code: 526 SECRET_SENTINEL')
  print('SECRET_SENTINEL',file=sys.stderr);sys.exit(22)
 if scenario=='bad-trace':print('SECRET_SENTINEL');sys.exit(0)
 reality=node.get('streamSettings',{}).get('realitySettings',{})
 bad=(reality.get('mldsa65Verify','BASEVERIFY')!='BASEVERIFY' or
      reality.get('shortId','aa')!='aa' or reality.get('fingerprint')=='hellochrome_120' or
      node['settings']['vnext'][0]['users'][0]['encryption']=='mlkem768x25519plus.NEW')
 if bad and scenario=='negative-526':
  Path(config['log']['error']).write_text('unexpected HTTP status 526 SECRET_SENTINEL');sys.exit(22)
 if bad and scenario!='wrong-credential-accepted':sys.exit(22)
 print('ip=203.0.113.10')
'''


class AuthResultsTests(unittest.TestCase):
    def run_harness(self, scenario):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            bins = work / 'bin'
            bins.mkdir()
            for command in ['xray', 'curl', 'ss']:
                file = bins / command
                file.write_text(FAKE)
                file.chmod(0o700)
            (work / 'server.json').write_text(json.dumps({'inbounds': [{'streamSettings': {'realitySettings': {'shortIds': ['aa']}}}]}))
            for node in ['a', 'b']:
                config = {'inbounds': [{'port': 1}], 'outbounds': [{'tag': 'node-' + node,
                    'settings': {'vnext': [{'users': [{'encryption': 'mlkem768x25519plus.BASE'}]}]},
                    'streamSettings': {'realitySettings': {'shortId': 'aa', 'mldsa65Verify': 'BASEVERIFY', 'fingerprint': 'chrome'}}}]}
                (work / f'client-{node}.json').write_text(json.dumps(config))
            environment = dict(os.environ, PATH=str(bins) + os.pathsep + os.environ['PATH'],
                               AUTH_TEST_WORK=str(work), AUTH_TEST_SCENARIO=scenario)
            result = subprocess.run(['bash', '-c', 'if "$@"; then printf "CALLER_PASS\\n"; else printf "CALLER_FAIL\\n"; exit 1; fi', '_',
                str(ROOT / 'tools/poc/check-live-auth.sh'), '--xray', str(bins / 'xray'), '--work-dir', str(work)],
                env=environment, capture_output=True, text=True, timeout=20)
            self.assertNotIn('SECRET_SENTINEL', result.stdout + result.stderr)
            self.assertFalse(list(work.glob('auth.*')))
            return result

    def test_b_failure_does_not_pass_and_a_is_reported(self):
        result = self.run_harness('fail-b')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[PASS] node-a-baseline', result.stdout)
        self.assertIn('[FAIL] node-b-baseline', result.stdout)
        self.assertIn('cf_origin_526=true', result.stdout)
        self.assertNotIn('[PASS] node-b-baseline', result.stdout)
        self.assertNotIn('AUTH_POC: PASS', result.stdout)

    def test_a_failure_does_not_hide_b(self):
        result = self.run_harness('fail-a')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[FAIL] node-a-baseline', result.stdout)
        self.assertIn('[PASS] node-b-baseline', result.stdout)

    def test_zero_exit_without_trace_is_not_success(self):
        result = self.run_harness('bad-trace')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('[PASS]', result.stdout)

    def test_config_failure_is_not_a_successful_negative_control(self):
        result = self.run_harness('config-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('reason=client-config-test', result.stdout)
        self.assertNotIn('[PASS]', result.stdout)

    def test_wrong_credentials_accepted_fail_validation(self):
        result = self.run_harness('wrong-credential-accepted')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[FAIL] node-a-wrong-mldsa-verification', result.stdout)
        self.assertNotIn('AUTH_POC: PASS', result.stdout)

    def test_all_expected_results_pass(self):
        result = self.run_harness('success')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('AUTH_POC: PASS', result.stdout)

    def test_526_is_not_a_successful_credential_rejection(self):
        result = self.run_harness('negative-526')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('[FAIL] node-a-wrong-mldsa-verification', result.stdout)
        self.assertNotIn('AUTH_POC: PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Offline ASN decision tests; no network or node credentials."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "asn", Path(__file__).resolve().parents[2] / "scripts/check-reality-asn.py")
asn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asn)


class ASNTests(unittest.TestCase):
    def check(self, source="1.1.1.1", targets=("8.8.8.8",), records=None):
        records = records or {"1.1.1.1": {13335}, "8.8.8.8": {13335}}
        def resolve(address, timeout):
            value = records[str(address)]
            if isinstance(value, Exception):
                raise value
            return value
        return asn.compare(source, targets, resolve=resolve)

    def test_match(self):
        self.assertEqual(self.check()["status"], "PASS")

    def test_difference_is_not_failure(self):
        result = self.check(records={"1.1.1.1": {13335}, "8.8.8.8": {15169}})
        self.assertEqual(result["status"], "WARN")
        self.assertIn("different=1", result["detail"])

    def test_mixed_answers_and_multi_origin(self):
        result = self.check(targets=["8.8.8.8", "9.9.9.9"], records={
            "1.1.1.1": {13335}, "8.8.8.8": {13335, 15169}, "9.9.9.9": {19281}})
        self.assertEqual(result["status"], "WARN")
        self.assertIn("matched=1; different=1", result["detail"])

    def test_no_raw_error_or_address_output(self):
        for records in [
            {"1.1.1.1": RuntimeError("SECRET")},
            {"1.1.1.1": {13335}, "8.8.8.8": RuntimeError("SECRET")},
        ]:
            result = self.check(records=records)
            self.assertEqual(result["status"], "WARN")
            self.assertNotIn("SECRET", result["detail"])
            self.assertNotIn("8.8.8.8", result["detail"])

    def test_self_target_and_mapped_ipv4(self):
        for target in ["1.1.1.1", "::ffff:1.1.1.1"]:
            self.assertEqual(self.check(targets=[target])["status"], "FAIL")

    def test_unknown_private_and_empty_inputs(self):
        for source, targets in [("", ["8.8.8.8"]), ("invalid", ["8.8.8.8"]),
                                ("10.0.0.1", ["8.8.8.8"]), ("1.1.1.1", []),
                                ("1.1.1.1", ["127.0.0.1"])]:
            self.assertEqual(self.check(source, targets)["status"], "WARN")

    def test_bound_queries_and_report_omitted(self):
        calls = []
        def resolve(address, timeout):
            calls.append(address)
            return {13335}
        result = asn.compare("1.1.1.1", [f"8.8.8.{n}" for n in range(1, 12)], resolve=resolve)
        self.assertEqual(len(calls), 9)
        self.assertEqual(result["status"], "WARN")
        self.assertIn("omitted=3", result["detail"])


if __name__ == "__main__":
    unittest.main()

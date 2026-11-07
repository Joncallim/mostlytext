#!/usr/bin/env python3
"""Reject incomplete native retention outcomes and foreign-host execution before preparation."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('retention', HERE / 'run-quicklook-retained-reply-probe.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def status(code=0):
    return {'returncode': code, 'timed_out': False, 'cancelled': False, 'app_cleanup_requested': []}


def good_log():
    return '\n'.join('QL_RETENTION_OBSERVATION live=true holders=' + str(i) + ' bytes=' + str(i * 1048576)
                     for i in range(1, 9)) + '\n' + MODULE.SUCCESS + '\n'


class NativeOutcomeTests(unittest.TestCase):
    def test_complete_original(self):
        MODULE.verify_outcome(good_log(), 0, status(), False)

    def test_only_named_live_reply_counterexample(self):
        MODULE.verify_outcome('QL_RETENTION_OBSERVATION live=true holders=0 bytes=0\nQL_RETENTION_FAILURE retained-before-factory\n',
                              42, status(42), True)

    def test_incomplete_original(self):
        with self.assertRaises(RuntimeError):
            MODULE.verify_outcome(MODULE.SUCCESS, 0, status(), False)

    def test_wrong_release_accounting(self):
        with self.assertRaises(RuntimeError):
            MODULE.verify_outcome(good_log().replace('bytes=8388608', 'bytes=0'), 0, status(), False)

    def test_duplicate_pass(self):
        with self.assertRaises(RuntimeError):
            MODULE.verify_outcome(good_log() + MODULE.SUCCESS, 0, status(), False)

    def test_hidden_failure(self):
        with self.assertRaises(RuntimeError):
            MODULE.verify_outcome(good_log() + 'QL_RETENTION_FAILURE another-reason\n', 0, status(), False)

    def test_refused_or_unexpected_run(self):
        for extra in ['QL_RETENTION_REFUSED foreign execution context', 'QL_RETENTION_UNEXPECTED error']:
            with self.assertRaises(RuntimeError):
                MODULE.verify_outcome(good_log() + extra, 0, status(), False)

    def test_wrong_counterexample_failure(self):
        for log in ['QL_RETENTION_FAILURE retained-before-factory\n',
                    'QL_RETENTION_OBSERVATION live=true holders=0 bytes=0\nQL_RETENTION_FAILURE reply-holder-retain-cycle\n']:
            with self.assertRaises(RuntimeError):
                MODULE.verify_outcome(log, 42, status(42), True)

    def test_wrong_returncode(self):
        with self.assertRaises(RuntimeError):
            MODULE.verify_outcome(good_log(), -11, status(-11), False)

    def test_timeout_cancellation_or_cleanup_cannot_pass(self):
        for key, value in [('timed_out', True), ('cancelled', True), ('app_cleanup_requested', [{'forced': True}])]:
            owned = status()
            owned[key] = value
            with self.assertRaises(RuntimeError):
                MODULE.verify_outcome(good_log(), 0, owned, False)

    def test_optimized_preparation_refuses(self):
        result = subprocess.run([sys.executable, '-O', str(HERE / 'run-quicklook-retained-reply-probe.py')],
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Optimized Python is refused before Quick Look retention preparation', result.stderr)


if __name__ == '__main__':
    unittest.main()

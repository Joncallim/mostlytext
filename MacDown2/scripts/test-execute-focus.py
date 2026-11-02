#!/usr/bin/env python3
"""Non-launch controls for the isolated executor's terminal verdict."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('executor', Path(__file__).with_name('execute-focus.py'))
executor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(executor)


class ExecutorVerdictTests(unittest.TestCase):
    def setUp(self):
        self.counts = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0,
                       'skippedTests': 0, 'expectedFailures': 0}

    def test_current_candidate_comes_from_the_reviewed_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory).resolve()
            self.assertEqual(executor.candidate_root({'candidateRoot': str(candidate)}), candidate)

    def test_missing_relative_noncanonical_or_non_directory_candidates_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            file = parent / 'file'
            file.write_text('not a checkout')
            alias = parent / 'alias'
            alias.symlink_to(parent, target_is_directory=True)
            for value in [None, 1, '', 'relative', str(parent) + '/../other',
                          str(parent) + '/', str(file), str(alias), str(parent / 'missing')]:
                with self.subTest(candidate=value):
                    with self.assertRaises((RuntimeError, FileNotFoundError)):
                        executor.candidate_root({'candidateRoot': value})
            with self.assertRaisesRegex(RuntimeError, 'candidate'):
                executor.candidate_root({})

    def test_one_complete_pass_is_accepted(self):
        self.assertTrue(executor.verified_pass(0, self.counts, False))

    def test_deadline_expiry_cannot_turn_into_a_pass_after_termination(self):
        self.assertFalse(executor.verified_pass(0, self.counts, True))

    def test_nonzero_exit_is_not_a_pass(self):
        self.assertFalse(executor.verified_pass(1, self.counts, False))

    def test_missing_or_changed_counts_are_not_a_pass(self):
        for name in self.counts:
            with self.subTest(name=name):
                missing = dict(self.counts)
                del missing[name]
                self.assertFalse(executor.verified_pass(0, missing, False))
                changed = dict(self.counts)
                changed[name] += 1
                self.assertFalse(executor.verified_pass(0, changed, False))

    def test_boolean_float_and_string_counts_are_not_integer_proof(self):
        for name, value in self.counts.items():
            for malformed in [bool(value), float(value), str(value), None]:
                with self.subTest(name=name, malformed=malformed):
                    counts = dict(self.counts)
                    counts[name] = malformed
                    self.assertFalse(executor.verified_pass(0, counts, False))

    def test_a_nonobject_summary_is_not_a_pass(self):
        for counts in [None, [], 1, 'complete']:
            self.assertFalse(executor.verified_pass(0, counts, False))

    def test_exit_and_timeout_types_do_not_borrow_boolean_equality(self):
        for exit_code in [False, 0.0, '0', None]:
            self.assertFalse(executor.verified_pass(exit_code, self.counts, False))
        for timeout in [0, None, 'false']:
            self.assertFalse(executor.verified_pass(0, self.counts, timeout))

    def test_execute_flag_cannot_bypass_owner_account_refusal(self):
        with mock.patch.object(executor.argparse.ArgumentParser, 'parse_args',
                               return_value=SimpleNamespace(execute=True)), \
                mock.patch.object(executor.os, 'getuid', return_value=501), \
                mock.patch.object(executor.os, 'geteuid', return_value=501), \
                mock.patch.object(executor, 'protected') as protection, \
                mock.patch.object(executor.subprocess, 'Popen') as launch:
            with self.assertRaisesRegex(RuntimeError, 'requires test UID 502'):
                executor.main()
            protection.assert_not_called()
            launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()

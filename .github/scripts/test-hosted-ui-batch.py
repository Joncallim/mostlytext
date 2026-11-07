#!/usr/bin/env python3
"""Actual host/anchor/attempt admission controls without reading any receipt."""
import ast
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name('run-hosted-ui-batch.py')


def read_order(source, anchor='0' * 40, receipt=None):
    tree = ast.parse(source)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'QUALIFIED_MAIN' for t in node.targets):
            node.value = ast.Constant(anchor)
    scope = {'__file__': str(SCRIPT), '__name__': 'read_order_control'}
    exec(compile(ast.fix_missing_locations(tree), str(SCRIPT), 'exec'), scope)
    reads, commands = [], []
    contract = {'batch': 'B01', 'cases': ['MacDown2UITests/Control/testNeverExecuted']}

    def intercept(path, *_args, **_kwargs):
        reads.append(str(path))
        if receipt is not None:
            return json.dumps(receipt)
        raise RuntimeError('Intercepted receipt read; no file opened')

    def ancestry(arguments, **_kwargs):
        if arguments != ['git', 'merge-base', '--is-ancestor', '0' * 40, 'HEAD']:
            raise RuntimeError('Unexpected command refused without execution')
        commands.append(arguments)
        return subprocess.CompletedProcess(arguments, 0)

    scope['selected_batch'] = lambda *_args: contract
    with mock.patch.dict(os.environ, {'RUNNER_TEMP': '/tmp/batch-read-order-control'}, clear=True), \
         mock.patch.object(sys, 'argv', [str(SCRIPT), 'execute', 'B01']), \
         mock.patch.object(subprocess, 'run', ancestry), \
         mock.patch.object(Path, 'read_text', intercept):
        try:
            scope['main']()
        except (RuntimeError, AssertionError) as error:
            return reads, commands, error
    raise AssertionError('Untrusted host unexpectedly admitted')


class BatchAdmissionControls(unittest.TestCase):
    def test_actual_host_precedes_ancestry_plan_and_receipt_read(self):
        source = SCRIPT.read_text()
        self.assertEqual(source.count('    guard.check_host(root)\n'), 1)
        reads, commands, error = read_order(source.replace('    guard.check_host(root)\n', ''))
        self.assertEqual(len(reads), 1)
        self.assertEqual(len(commands), 1)
        self.assertIn('Intercepted receipt read', str(error))
        reads, commands, error = read_order(source)
        self.assertEqual((reads, commands), ([], []))
        self.assertNotIn('Intercepted receipt read', str(error))

    def test_held_anchor_refuses_before_host_plan_and_receipt(self):
        reads, commands, error = read_order(SCRIPT.read_text(), 'PENDING_CONTROL')
        self.assertEqual((reads, commands), ([], []))
        self.assertIn('UI-batch execution is held', str(error))

    def test_actual_attempt_and_retarget_guards_stop_before_product_or_native_commands(self):
        source = SCRIPT.read_text().replace('    guard.check_host(root)\n', '')
        contract = {'batch': 'B01', 'cases': ['MacDown2UITests/Control/testNeverExecuted']}
        for receipt in [{'batch_contract': contract, 'execution_started': True},
                        {'batch_contract': contract, 'execution_started': False, 'batch_cases': []}]:
            reads, commands, error = read_order(source, receipt=receipt)
            self.assertEqual(len(reads), 1)
            self.assertEqual(len(commands), 1)  # Intercepted ancestry only; no command executed.
            self.assertRegex(str(error), 'previously attempted|retargeted')

    def test_optimized_interpreter_refuses_before_environment(self):
        result = subprocess.run([sys.executable, '-B', '-O', str(SCRIPT), 'prepare', 'B01'],
                                capture_output=True, env={'PATH': os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b'Optimized Python is refused', result.stderr)
        self.assertNotIn(b'RUNNER_TEMP', result.stderr)


class ActualNativeOutcomeControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import gzip
        root = SCRIPT.resolve().parents[2]
        packet = root / 'planning/downstream/evidence/qualified-startup-status-2026-11-07'
        prefix = 'ed96-status-layout--hosted-normal-status-layout--'
        receipt = json.loads(gzip.decompress((packet / (prefix + 'receipt.json.gz')).read_bytes()))
        row = receipt['ui_results']['focus']
        cls.passed = [row['summary'], row['owned'], 0,
                      gzip.decompress((packet / (prefix + 'focus.log.gz')).read_bytes()).decode(), row['selected']]
        packet = root / 'planning/downstream/evidence/status-bar-layout-2026-11-07'
        receipt = json.loads(gzip.decompress((packet / '8e2c-status-receipt.json.gz').read_bytes()))
        row = receipt['ui_results']['focus']
        cls.failed = [row['summary'], row['owned'], 65,
                      gzip.decompress((packet / '8e2c-status-focus.log.gz').read_bytes()).decode(), row['selected']]
        scope = {'__file__': str(SCRIPT), '__name__': 'actual_outcome_control'}
        exec(compile(ast.parse(SCRIPT.read_text()), str(SCRIPT), 'exec'), scope)
        cls.classify = staticmethod(scope['require_exact_case_outcome'])

    def test_actual_original_geometry_failure_and_corrected_pass_stay_distinct(self):
        self.assertTrue(self.classify(*self.passed))
        self.assertFalse(self.classify(*self.failed))

    def test_zero_multiple_skipped_expected_or_boolean_counts_never_pass(self):
        for key, value in [('totalTestCount', 0), ('totalTestCount', 2), ('skippedTests', 1),
                           ('expectedFailures', 1), ('passedTests', True), ('failedTests', False)]:
            row = copy.deepcopy(self.passed)
            row[0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                self.classify(*row)

    def test_wrong_identity_repeat_or_framework_restart_is_not_a_pass(self):
        for index, value in [(4, 'MacDown2UITests/Wrong/testWrong'),
                             (3, self.passed[3] + self.passed[3]),
                             (3, self.passed[3] + '\nRestarting after unexpected framework exception')]:
            row = copy.deepcopy(self.passed)
            row[index] = value
            with self.assertRaises(RuntimeError):
                self.classify(*row)

    def test_uncertain_cleanup_timeout_cancel_or_mismatched_exit_stops_admission(self):
        for key, value in [('timed_out', True), ('cancelled', True),
                           ('app_cleanup_requested', [{'pid': 123, 'birth': 456}]),
                           ('returncode', 65), ('returncode', False)]:
            row = copy.deepcopy(self.passed)
            row[1][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                self.classify(*row)


if __name__ == '__main__':
    if sys.flags.optimize:
        raise RuntimeError('Run admission controls normally; optimized refusal is tested in a child')
    unittest.main()

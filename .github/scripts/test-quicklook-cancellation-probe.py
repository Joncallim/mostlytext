#!/usr/bin/env python3
"""Validate precise actual-event correlation; synthetic rows are parser controls only."""
import copy
import gzip
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('cancellation_probe', HERE / 'prepare-quicklook-cancellation-probe.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def observation(cancelled=False):
    return {'kind': 'mostlytext-qlcancel-observation', 'selected': 'mostlytext-ql-reply-cancel.md', 'request_id': 1,
            'provider_started': 100.0, 'observed_pending': 101.0, 'escape_sent': 102.0, 'window_closed': 103.0,
            'provider_terminal': 102.5 if cancelled else 110.0,
            'terminal_kind': 'terminal-cancelled' if cancelled else 'terminal-completed',
            'system_task_cancellation_observed': cancelled}


def messages(cancelled=False):
    return ['QL_CANCEL_PROBE pending id=1 uptime=100.000000'] + (
        ['QL_CANCEL_PROBE handler id=1 uptime=102.100000', 'QL_CANCEL_PROBE terminal-cancelled id=1 uptime=102.500000']
        if cancelled else ['QL_CANCEL_PROBE terminal-completed id=1 uptime=110.000000'])


class PendingFinderObservationTests(unittest.TestCase):
    def test_delayed_completion_is_recorded_as_no_system_task_cancellation(self):
        MODULE.validate_observation(observation(), messages())

    def test_actual_cancellation_may_precede_observed_window_disappearance(self):
        MODULE.validate_observation(observation(True), messages(True))

    def test_wrong_file_or_kind(self):
        for key in ['selected', 'kind']:
            row = observation(); row[key] = 'another'
            with self.assertRaises(RuntimeError): MODULE.validate_observation(row, messages())

    def test_missing_or_nonfinite_time(self):
        for value in [None, float('nan'), float('inf'), True]:
            row = observation(); row['window_closed'] = value
            with self.assertRaises(RuntimeError): MODULE.validate_observation(row, messages())

    def test_request_already_completed_before_escape(self):
        row = observation(); row['provider_terminal'] = 101.5
        with self.assertRaises(RuntimeError): MODULE.validate_observation(row, messages())

    def test_completed_work_during_escape_is_not_pending_at_actual_close(self):
        row = observation(); row['provider_terminal'] = 102.5
        with self.assertRaises(RuntimeError): MODULE.validate_observation(row, ['QL_CANCEL_PROBE pending id=1 uptime=100.000000', 'QL_CANCEL_PROBE terminal-completed id=1 uptime=102.500000'])

    def test_wrong_request_identity(self):
        row = observation(); row['request_id'] = 2
        with self.assertRaises(RuntimeError): MODULE.validate_observation(row, messages())

    def test_extra_pending_or_terminal(self):
        for extra in messages():
            with self.assertRaises(RuntimeError): MODULE.validate_observation(observation(), messages() + [extra])

    def test_disagreed_ui_and_provider_terminal(self):
        row = observation(); row['provider_terminal'] = 111.0
        with self.assertRaises(RuntimeError): MODULE.validate_observation(row, messages())

    def test_missing_actual_handler(self):
        with self.assertRaises(RuntimeError): MODULE.validate_observation(observation(True), [messages(True)[0], messages(True)[2]])

    def test_cancelled_before_escape_cannot_be_attributed_to_escape(self):
        with self.assertRaises(RuntimeError): MODULE.validate_observation(observation(True), [messages(True)[0], 'QL_CANCEL_PROBE handler id=1 uptime=101.500000', messages(True)[2]])

    def test_false_cancellation_claim(self):
        row = observation(); row['system_task_cancellation_observed'] = True
        with self.assertRaises(RuntimeError): MODULE.validate_observation(row, messages())

    def test_actual_test_injected_permissions_rejected(self):
        root = HERE.parent.parent
        actual = json.loads(gzip.decompress((root / 'planning/downstream/evidence/quicklook-hosted-feasibility-2026-11-07/b000-receipt.json.gz').read_bytes()))['built']['entitlements']
        with self.assertRaises(AssertionError): MODULE.validate_provider_entitlements(actual)
        MODULE.validate_provider_entitlements({'com.apple.security.app-sandbox': True, 'com.apple.security.files.user-selected.read-only': True})

    def test_foreign_pr_refused(self):
        with self.assertRaises(RuntimeError): MODULE.validate_trusted_event({'pull_request': {'head': {'repo': {'full_name': 'foreign/fork'}}}}, 'pull_request')

    def test_optimized_preparation_refuses_before_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'must-not-create'
            result = subprocess.run([sys.executable, '-O', str(HERE / 'prepare-quicklook-cancellation-probe.py'), str(target)], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Optimized Python cannot enforce', result.stderr)
            self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()

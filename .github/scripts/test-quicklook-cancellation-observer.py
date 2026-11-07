#!/usr/bin/env python3
"""Adversarial temporary-file controls for actual observation publication and ownership."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('observer', HERE / 'observe-quicklook-cancellation.py')
OBSERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBSERVER)
PREP = OBSERVER.PREP


def fixture(root):
    rows = [OBSERVER.publish(root, [], 0, 'source'), OBSERVER.publish(root, ['actual provider event'], 1, 'source')]
    for row in rows: row['command_returncode'] = 0
    driver = {'checkout': 'source', 'errors': [], 'ui_started': True, 'ui_supervisor_returncode': 0,
              'observer_forced_cleanup': False, 'observer_returncode': 0, 'observer_pid': 123,
              'ui_completed_monotonic': 10, 'observer_stop_requested_monotonic': 11}
    observed = {'checkout': 'source', 'errors': [], 'timed_out': False, 'stopped_after_ui': True,
                'pid': 123, 'snapshots': rows, 'successful_log_queries': 3}
    (root / 'host-ui-driver.json').write_text(json.dumps(driver))
    (root / 'observer-result.json').write_text(json.dumps(observed))
    return driver, observed


class HostObservationTests(unittest.TestCase):
    def test_actual_bytes_remain_immutable_and_current_is_exact_last_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); fixture(root)
            PREP.validate_host_observer(root, 'source')
            self.assertEqual((root / 'provider-observer.json').stat().st_mode & 0o777, 0o600)
            first = (root / 'observer-journal/000.json').read_bytes()
            self.assertEqual(json.loads(first)['messages'], [])
            self.assertEqual(json.loads((root / 'provider-observer.json').read_text())['messages'], ['actual provider event'])

    def test_duplicate_generation_cannot_replace_first_or_current(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); fixture(root)
            before = (root / 'provider-observer.json').read_bytes()
            with self.assertRaises(FileExistsError): OBSERVER.publish(root, ['forged'], 0, 'source')
            self.assertEqual((root / 'provider-observer.json').read_bytes(), before)

    def test_budget_and_unknown_message_refuse_before_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for values, sequence in [(['x' * 131072], 0), ([], 128), ([None], 0), ([], -1)]:
                with self.assertRaises(RuntimeError): OBSERVER.publish(root, values, sequence, 'source')
            self.assertFalse((root / 'provider-observer.json').exists())

    def reject_driver(self, key, value):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); driver, _ = fixture(root); driver[key] = value
            (root / 'host-ui-driver.json').write_text(json.dumps(driver))
            with self.assertRaises(RuntimeError): PREP.validate_host_observer(root, 'source')

    def test_forced_or_nonzero_ui_or_recorder_cannot_pass(self):
        for key, value in [('observer_forced_cleanup', True), ('observer_returncode', 1), ('ui_supervisor_returncode', 65)]:
            self.reject_driver(key, value)

    def test_early_recorder_stop_or_wrong_identity_cannot_pass(self):
        self.reject_driver('observer_stop_requested_monotonic', 9)
        self.reject_driver('observer_pid', 456)

    def test_wrong_checkout_cannot_pass(self):
        self.reject_driver('checkout', 'another-source')

    def test_changed_bytes_or_stale_current_cannot_pass(self):
        for filename in ['observer-journal/001.json', 'provider-observer.json']:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); fixture(root); (root / filename).write_bytes(b'{}')
                with self.assertRaises(RuntimeError): PREP.validate_host_observer(root, 'source')

    def test_failed_log_command_or_timeout_cannot_pass(self):
        for mutation in ['command', 'timeout', 'errors']:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); _, observed = fixture(root)
                if mutation == 'command': observed['snapshots'][0]['command_returncode'] = 64
                elif mutation == 'timeout': observed['timed_out'] = True
                else: observed['errors'] = ['actual query failed']
                (root / 'observer-result.json').write_text(json.dumps(observed))
                with self.assertRaises(RuntimeError): PREP.validate_host_observer(root, 'source')

    def test_optimized_observer_and_driver_refuse_before_preparation(self):
        for script in ['observe-quicklook-cancellation.py', 'run-quicklook-cancellation-ui.py']:
            result = subprocess.run([sys.executable, '-O', str(HERE / script)], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Optimized Python cannot enforce', result.stderr)


if __name__ == '__main__':
    unittest.main()

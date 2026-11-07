#!/usr/bin/env python3
"""Adversarial temporary-file controls for actual observation publication and ownership."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import hashlib

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('observer', HERE / 'observe-quicklook-deadline.py')
OBSERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBSERVER)
PREP = OBSERVER.PREP


def fixture(root):
    rows = [OBSERVER.publish(root, [], 0, 'source'), OBSERVER.publish(root, ['actual provider event'], 1, 'source')]
    nonce = 'E746CCCB-EE80-4F3B-817A-C2E5467373BC'
    echo = json.dumps({'subsystem': PREP.CONTROL_SUBSYSTEM, 'eventMessage': 'QL_OBSERVER_CONTROL nonce=' + nonce}).encode() + b'\n'
    event = json.dumps({'subsystem': PREP.PROVIDER_SUBSYSTEM, 'eventMessage': 'actual provider event'}).encode() + b'\n'
    raw = echo + event
    rows[0]['stream_position'] = len(echo)
    rows[1]['stream_position'] = len(raw)
    (root / 'observer-stream.log').write_bytes(raw)
    (root / 'observer-stream-errors.txt').write_bytes(b'')
    (root / 'observer-control').write_bytes(b'Pure test bytes; never executable')
    binary_sha = PREP.digest(root / 'observer-control')
    (root / 'observer-control-build.json').write_text(json.dumps({'returncode': 0, 'binary_sha256': binary_sha}))
    driver = {'checkout': 'source', 'errors': [], 'ui_started': True, 'ui_supervisor_returncode': 0,
              'observer_forced_cleanup': False, 'observer_returncode': 0, 'observer_pid': 123,
              'ui_completed_monotonic': 10, 'observer_stop_requested_monotonic': 11}
    observed = {'checkout': 'source', 'errors': [], 'timed_out': False, 'stopped_after_ui': True,
                'pid': 123, 'snapshots': rows, 'mode': 'live-ndjson', 'stream_command': PREP.STREAM_COMMAND,
                'stream_forced_cleanup': False, 'stream_returncode': -15, 'stream_unexpected_exit': False,
                'nonce': nonce, 'control_sha256': binary_sha,
                'control_attempts': [{'command': [str(root / 'observer-control'), nonce], 'returncode': 0}],
                'stream_bytes': len(raw), 'stream_sha256': hashlib.sha256(raw).hexdigest()}
    observed.update(started_monotonic=0, admitted_monotonic=1, stop_signal_monotonic=12, finished_monotonic=13)
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

    def test_failed_stream_or_control_or_timeout_cannot_pass(self):
        for mutation in ['command', 'timeout', 'errors', 'unexpected_exit', 'forced', 'control', 'position', 'nonce', 'raw', 'stderr', 'late_echo', 'early_stream_stop']:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); _, observed = fixture(root)
                if mutation == 'command': observed['stream_returncode'] = 64
                elif mutation == 'timeout': observed['timed_out'] = True
                elif mutation == 'errors': observed['errors'] = ['actual stream failed']
                elif mutation == 'unexpected_exit': observed['stream_unexpected_exit'] = True
                elif mutation == 'forced': observed['stream_forced_cleanup'] = True
                elif mutation == 'control': observed['control_attempts'][0]['returncode'] = 1
                elif mutation == 'position': observed['snapshots'][0]['stream_position'] += 1
                elif mutation == 'nonce': observed['nonce'] = 'C411C903-75AB-4274-8501-4C0F3A51AF50'
                elif mutation == 'raw': (root / 'observer-stream.log').write_bytes(b'{}\n')
                elif mutation == 'stderr': (root / 'observer-stream-errors.txt').write_bytes(b'dropped record')
                elif mutation == 'late_echo': observed['admitted_monotonic'] = 5
                elif mutation == 'early_stream_stop': observed['stop_signal_monotonic'] = 9
                (root / 'observer-result.json').write_text(json.dumps(observed))
                with self.assertRaises(RuntimeError): PREP.validate_host_observer(root, 'source')

    def test_compiled_control_change_or_missing_success_cannot_pass(self):
        for filename in ['observer-control', 'observer-control-build.json']:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); fixture(root)
                (root / filename).write_bytes(b'{}')
                with self.assertRaises(RuntimeError): PREP.validate_host_observer(root, 'source')

    def test_malformed_unknown_namespace_and_truncated_stream_cannot_admit(self):
        for raw in [b'{}\n', b'not-json\n', b'[]\n', b'x' * 131073,
                    b'{"subsystem":"another.app","eventMessage":"data"}\n']:
            with self.assertRaises(RuntimeError): PREP.parse_live_record(raw)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); _, observed = fixture(root)
            raw = (root / 'observer-stream.log').read_bytes()
            with self.assertRaises(RuntimeError): PREP.replay_live_stream(raw[:-1], observed['nonce'])

    def test_wrong_nonce_or_provider_namespace_cannot_supply_channel_echo(self):
        nonce = 'E746CCCB-EE80-4F3B-817A-C2E5467373BC'
        for namespace, value in [(PREP.PROVIDER_SUBSYSTEM, nonce), (PREP.CONTROL_SUBSYSTEM, nonce.lower())]:
            event = {'subsystem': namespace, 'eventMessage': 'QL_OBSERVER_CONTROL nonce=' + value}
            self.assertFalse(PREP.is_control_echo(event, nonce))
            with self.assertRaises(RuntimeError): PREP.replay_live_stream(json.dumps(event).encode() + b'\n', nonce)

    def test_filtering_metadata_is_never_channel_readiness(self):
        raw = b'Filtering the log data using a predicate\n'
        self.assertIsNone(PREP.parse_live_record(raw))
        with self.assertRaises(RuntimeError): PREP.replay_live_stream(raw, 'E746CCCB-EE80-4F3B-817A-C2E5467373BC')

    def test_optimized_observer_and_driver_refuse_before_preparation(self):
        for script in ['observe-quicklook-deadline.py', 'run-quicklook-deadline-ui.py']:
            result = subprocess.run([sys.executable, '-O', str(HERE / script)], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Optimized Python cannot enforce', result.stderr)


if __name__ == '__main__':
    unittest.main()

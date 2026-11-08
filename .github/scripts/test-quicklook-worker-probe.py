#!/usr/bin/env python3
"""Pure worker-wire/authority controls only; no process, GUI or engine is executed."""
import copy
import base64
import hashlib
import tempfile
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('worker_preparation', Path(__file__).with_name('prepare-quicklook-jsc-probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
SHA = 'a' * 64


def fixture():
    children = [dict(request_id=3, mode=m, pid=p, ppid=100, sandbox=True, inherit=True,
                     reason=r, status=s, gone=True, elapsed_ms=t)
                for m, p, r, s, t in [('normal', 101, 'exit', 0, 12), ('held', 102, 'signal', 9, 550)]]
    return dict(kind='mostlytext-qlworker-capability', request_id=3, provider_pid=100,
                started_uptime=123.0, worker_sha256=SHA, children=children)


def messages(value):
    return ['QL_WORKER_PROBE begin id=3 parent=100 start=123.000000',
            'QL_WORKER_PROBE executable id=3 sha256=' + SHA,
            *['QL_WORKER_PROBE child=' + json.dumps(c, separators=(',', ':')) for c in value['children']],
            'QL_WORKER_PROBE factory id=3 bytes=350']


class ActualWorkerEvidence(unittest.TestCase):
    def test_exact_normal_and_reaped_deadline_records_are_admitted(self):
        row = fixture()
        probe.validate_worker_observation(row, messages(row), SHA)

    def test_added_network_or_jit_authority_and_integer_flags_refuse(self):
        expected = {'com.apple.security.app-sandbox': True, 'com.apple.security.inherit': True}
        probe.validate_worker_entitlements(expected)
        for key in ['com.apple.security.network.client', 'com.apple.security.cs.allow-jit']:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                probe.validate_worker_entitlements(dict(expected, **{key: True}))
        with self.assertRaises(RuntimeError):
            probe.validate_worker_entitlements(dict(expected, **{'com.apple.security.inherit': 1}))

    def test_false_reaped_flag_wrong_parent_and_reused_pid_refuse(self):
        for key, value in [('gone', False), ('ppid', 999), ('pid', 101), ('pid', True)]:
            row = fixture(); row['children'][1][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                probe.validate_worker_observation(row, messages(row), SHA)

    def test_wrong_signal_normal_exit_and_unbounded_or_premature_deadline_refuse(self):
        for key, value in [('status', 15), ('reason', 'exit'), ('elapsed_ms', 3000), ('elapsed_ms', 2)]:
            row = fixture(); row['children'][1][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                probe.validate_worker_observation(row, messages(row), SHA)

    def test_missing_duplicate_or_other_request_log_refuses(self):
        row = fixture(); original = messages(row)
        for logs in [original[:-1], original[:2] + original[3:], original + [original[2]],
                     [s.replace('"request_id":3', '"request_id":4') for s in original]]:
            with self.assertRaises(RuntimeError):
                probe.validate_worker_observation(row, logs, SHA)

    def test_wrong_actual_compiled_worker_or_factory_refuses(self):
        row = fixture()
        with self.assertRaises(RuntimeError):
            probe.validate_worker_observation(row, messages(row), 'b' * 64)
        for changed in ['QL_WORKER_PROBE factory id=3 bytes=8193', 'QL_WORKER_PROBE factory id=4 bytes=350']:
            logs = messages(row); logs[-1] = changed
            with self.assertRaises(RuntimeError):
                probe.validate_worker_observation(row, logs, SHA)

    def test_missing_or_unknown_child_metadata_and_nonfinite_clock_refuse(self):
        for change in ['missing', 'extra', 'clock']:
            row = copy.deepcopy(fixture())
            if change == 'missing': del row['children'][0]['inherit']
            elif change == 'extra': row['children'][0]['simulation'] = True
            else: row['started_uptime'] = float('nan')
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                probe.validate_worker_observation(row, messages(row), SHA)


def spawn_fixture():
    error = dict(domain='NSCocoaErrorDomain', code=4, description='Actual harmless test error',
                 domain_utf8_bytes=18, description_utf8_bytes=26)
    row = dict(kind='mostlytext-qlworker-spawn-error', request_id=3, provider_pid=100,
               mode='normal', error=error, underlying=[], worker_path='/fixture/Provider.appex/Contents/MacOS/QLReplyProbeWorker',
               unix_permissions=493, read_access=0, read_errno=0, execute_access=0, execute_errno=0,
               current_directory='/', process_directory=None)
    return row


def spawn_messages(row):
    raw = json.dumps(row, separators=(',', ':')).encode()
    count = (len(raw) + 383) // 384
    digest = hashlib.sha256(raw).hexdigest()
    return ['QL_WORKER_PROBE begin id=3 parent=100 start=123.000000',
            'QL_WORKER_PROBE executable id=3 sha256=' + SHA,
            *[f'QL_WORKER_PROBE spawn-error id=3 part={i} total={count} sha256={digest} data=' +
              base64.b64encode(raw[i * 384:(i + 1) * 384]).decode() for i in range(count)],
            'QL_WORKER_PROBE spawn-refused id=3 code=4']


class PreciseSpawnFailureEvidence(unittest.TestCase):
    def test_complete_actual_error_has_exact_file_and_error_observations(self):
        row = spawn_fixture()
        self.assertEqual(probe.decode_worker_spawn_errors(spawn_messages(row), SHA), [row])
        self.assertEqual(probe.decode_worker_spawn_errors([], SHA), [])

    def test_missing_duplicate_corrupt_or_excessive_frames_refuse(self):
        original = spawn_messages(spawn_fixture())
        for logs in [original[:2] + original[3:], original + [original[2]],
                     [m.replace('sha256=', 'sha256=0', 1) if 'spawn-error' in m else m for m in original],
                     [m[:180] if 'spawn-error' in m else m for m in original]]:
            with self.subTest(logs=logs), self.assertRaises((RuntimeError, ValueError)):
                probe.decode_worker_spawn_errors(logs, SHA)

    def test_other_request_provider_worker_and_unexplained_refusal_refuse(self):
        original = spawn_messages(spawn_fixture())
        for logs in [[m.replace('id=3', 'id=4') if 'spawn-error' in m else m for m in original],
                     [m.replace('parent=100', 'parent=999') for m in original],
                     original + ['QL_WORKER_PROBE spawn-refused id=4 code=4'],
                     [m.replace(SHA, 'b' * 64) for m in original]]:
            with self.assertRaises(RuntimeError): probe.decode_worker_spawn_errors(logs, SHA)

    def test_unknown_schema_noninteger_error_and_excessive_fields_refuse(self):
        for change in ['extra', 'code', 'description', 'pid', 'underlying']:
            row = spawn_fixture()
            if change == 'extra': row['invented_sandbox_denial'] = True
            elif change == 'code': row['error']['code'] = True
            elif change == 'description': row['error']['description'] = 'x' * 513
            elif change == 'pid': row['provider_pid'] = True
            else: row['underlying'] = [row['error']] * 3
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                probe.decode_worker_spawn_errors(spawn_messages(row), SHA)

    def test_failed_ui_recording_can_be_retained_but_never_qualifies_success(self):
        spec = importlib.util.spec_from_file_location('observer_controls', Path(__file__).with_name('test-quicklook-jsc-observer.py'))
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); driver, _ = module.fixture(root)
            driver['ui_supervisor_returncode'] = 65
            (root / 'host-ui-driver.json').write_text(json.dumps(driver))
            proof = probe.validate_host_recording(root, 'source')
            self.assertEqual(proof['driver']['ui_supervisor_returncode'], 65)
            probe.retain_worker_spawn_errors(root, 'source', SHA)
            actual = json.loads((root / 'worker-spawn-errors.json').read_text())
            self.assertEqual(actual['actual_ui_returncode'], 65)
            self.assertFalse(actual['qualification_candidate'])
            with self.assertRaises(RuntimeError): probe.validate_host_observer(root, 'source')


if __name__ == '__main__':
    unittest.main()

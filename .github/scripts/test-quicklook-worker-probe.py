#!/usr/bin/env python3
"""Pure worker-wire/authority controls only; no process, GUI or engine is executed."""
import copy
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


if __name__ == '__main__':
    unittest.main()

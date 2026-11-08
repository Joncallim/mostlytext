#!/usr/bin/env python3
"""Pure XPC process/own-request controls; no service or product is launched."""
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('xpc_probe', HERE / 'prepare-quicklook-jsc-probe.py')
PREP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREP)


def example():
    record = {'kind': 'mostlytext-qlxpc-capability', 'request_id': 3,
              'provider_pid': 111, 'service_pid': 222, 'started_uptime': 12.5}
    messages = ['QL_XPC_PROBE begin id=3 provider=111 start=12.5',
                'QL_XPC_SERVICE replied id=3 pid=222 sandbox=1',
                'QL_XPC_PROBE admitted id=3 provider=111 service=222']
    return record, messages


class XPCObservationTests(unittest.TestCase):
    def test_one_exact_observation_passes(self):
        row, messages = example()
        PREP.validate_xpc_observation(row, messages)

    def test_missing_or_duplicate_process_evidence_refuses(self):
        row, messages = example()
        for bad in (messages[:1], messages[1:], messages[:2], messages[::2],
                    messages + messages[:1], messages + messages[1:2], messages + messages[2:]):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_observation(row, bad)

    def test_wrong_request_or_process_refuses(self):
        row, messages = example()
        for bad in ('QL_XPC_PROBE admitted id=4 provider=111 service=222',
                    'QL_XPC_PROBE admitted id=3 provider=111 service=111',
                    'QL_XPC_PROBE admitted id=3 provider=999 service=222'):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_observation(row, messages[:2] + [bad])
        with self.assertRaises(RuntimeError):
            PREP.validate_xpc_observation(row, [messages[0],
                                                'QL_XPC_SERVICE replied id=3 pid=333 sandbox=1', messages[2]])

    def test_invalid_types_and_extra_fields_refuse(self):
        row, messages = example()
        for key, value in (('service_pid', True), ('request_id', 0), ('started_uptime', float('nan')),
                           ('provider_pid', '111')):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_observation(dict(row, **{key: value}), messages)
        with self.assertRaises(RuntimeError):
            PREP.validate_xpc_observation(dict(row, fabricated=True), messages)

    def test_provider_authority_remains_minimal(self):
        PREP.validate_provider_entitlements({'com.apple.security.app-sandbox': True,
                                             'com.apple.security.files.user-selected.read-only': True})
        with self.assertRaises(AssertionError):
            PREP.validate_provider_entitlements({'com.apple.security.app-sandbox': True,
                                                 'com.apple.security.files.user-selected.read-only': True,
                                                 'com.apple.security.temporary-exception.mach-lookup.global-name': True})


if __name__ == '__main__':
    unittest.main()

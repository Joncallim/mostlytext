#!/usr/bin/env python3
"""Pure adversarial controls for distinct actual renderer/reply/visible-window events."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import unittest
sys.dont_write_bytecode = True
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('deadline_prep',HERE/'prepare-quicklook-deadline-probe.py')
PREP=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(PREP)


def valid():
    observation={'kind':'mostlytext-qldeadline-observation','small_request_id':2,'large_request_id':3,
                 'fallback_visible':4.3,'large_worker_terminal':5.0}
    events=[(2,'callback',1.0),(2,'worker-start',1.01),(2,'worker-terminal',1.2),
            (2,'selected-rich',1.21),(2,'reply-rich',1.22),(2,'factory-rich',1.3),
            (3,'callback',2.0),(3,'worker-start',2.01),(3,'selected-fallback',4.0),
            (3,'reply-fallback',4.01),(3,'factory-fallback',4.1),(3,'worker-terminal',5.0),(3,'late-error',5.1)]
    messages=[f'QL_DEADLINE_PROBE {phase} id={identifier} uptime={time}' for identifier,phase,time in events]
    messages += [f'QL_DEADLINE_BYTES id={i} bytes=123 sha256='+('a' if i==2 else 'b')*64 for i in [2,3]]
    return observation,messages


class RendererCorrelationTests(unittest.TestCase):
    def test_actual_distinct_rich_and_pending_fallback_control(self):
        PREP.validate_observation(*valid())

    def test_repeated_factory_requires_the_same_frozen_bytes(self):
        o,m=valid();m+=['QL_DEADLINE_PROBE factory-fallback id=3 uptime=4.2',
                        'QL_DEADLINE_BYTES id=3 bytes=123 sha256='+'b'*64]
        PREP.validate_observation(o,m)
        m[-1]='QL_DEADLINE_BYTES id=3 bytes=124 sha256='+'c'*64
        with self.assertRaises(RuntimeError):PREP.validate_observation(o,m)

    def test_same_unknown_bool_or_missing_request_refuses(self):
        for key,value in [('small_request_id',3),('small_request_id',True),('large_request_id',None),('kind','another')]:
            o,m=valid();o[key]=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(o,m)

    def test_no_visible_pending_overlap_or_nonfinite_time_refuses(self):
        for value in [5.0,5.1,3.0,None,math.nan,math.inf]:
            o,m=valid();o['fallback_visible']=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(o,m)

    def test_every_actual_phase_and_byte_record_is_required(self):
        o,m=valid()
        for index in range(len(m)):
            if 'late-error' in m[index] or 'QL_DEADLINE' in m[index]:
                with self.assertRaises(RuntimeError):PREP.validate_observation(o,m[:index]+m[index+1:])

    def test_double_terminal_or_wrong_worker_identity_refuses(self):
        for extra in ['QL_DEADLINE_PROBE selected-rich id=3 uptime=4.5',
                      'QL_DEADLINE_PROBE worker-terminal id=3 uptime=6.0']:
            o,m=valid()
            with self.assertRaises(RuntimeError):PREP.validate_observation(o,m+[extra])
        o,m=valid();m=[x.replace('worker-start id=3','worker-start id=4') for x in m]
        with self.assertRaises(RuntimeError):PREP.validate_observation(o,m)

    def test_factory_before_reply_or_rich_before_actual_api_return_refuses(self):
        for previous,next_value in [('reply-fallback id=3 uptime=4.01','reply-fallback id=3 uptime=4.25'),
                                    ('selected-rich id=2 uptime=1.21','selected-rich id=2 uptime=1.1')]:
            o,m=valid();m=[x.replace(previous,next_value) for x in m]
            with self.assertRaises(RuntimeError):PREP.validate_observation(o,m)

    def test_overbudget_or_changed_factory_bytes_refuse(self):
        o,m=valid();m=[x.replace('bytes=123','bytes=16777217') for x in m]
        with self.assertRaises(RuntimeError):PREP.validate_observation(o,m)

    def test_unknown_or_enlarged_provider_permissions_refuse(self):
        expected={'com.apple.security.app-sandbox':True,'com.apple.security.files.user-selected.read-only':True}
        PREP.validate_provider_entitlements(expected)
        for key in ['com.apple.security.network.client','com.apple.security.get-task-allow',
                    'com.apple.security.temporary-exception.files.absolute-path.read-only']:
            with self.assertRaises(AssertionError):PREP.validate_provider_entitlements(dict(expected,**{key:True}))

    def test_foreign_pull_request_refuses(self):
        with self.assertRaises(RuntimeError):PREP.validate_trusted_event({'pull_request':{'head':{'repo':{'full_name':'foreign/repo'}}}},'pull_request')

    def test_optimized_python_refuses_before_host_or_argument_access(self):
        for name in ['prepare-quicklook-deadline-probe.py','observe-quicklook-deadline.py','run-quicklook-deadline-ui.py']:
            result=subprocess.run([sys.executable,'-O',str(HERE/name)],capture_output=True,text=True,timeout=10)
            self.assertNotEqual(result.returncode,0);self.assertIn('Optimized Python cannot enforce',result.stderr)


if __name__=='__main__':unittest.main()

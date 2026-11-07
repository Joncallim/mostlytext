#!/usr/bin/env python3
"""Pure wire/correlation controls; no JavaScript engine is executed locally."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('jsc',HERE/'prepare-quicklook-jsc-probe.py')
PREP=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(PREP)


def fixture(status='available'):
    row={'kind':'mostlytext-qljsc-capability','request_id':2,'baseJS':42,'moduleHex':PREP.WASM_HEX,
         'started_uptime':100.0,'observed_uptime':100.1,'wasmType':'object',
         'workerType':'undefined','domType':'undefined','fetchType':'undefined','objcType':'undefined',
         'wasmStatus':status,'wasmAnswer':42,'errorPhase':None,'errorName':None,'errorMessage':None}
    if status=='unavailable':row.update(wasmType='undefined',wasmAnswer=None)
    if status=='error':row.update(wasmAnswer=None,errorPhase='module',errorName='CompileError',errorMessage='Actual bounded diagnostic')
    return row


def messages(row):return ['QL_JSC_PROBE result='+json.dumps(row),'QL_JSC_PROBE factory id=2 bytes=1000']


class JavaScriptCapabilityTests(unittest.TestCase):
    def test_supported_missing_global_and_error_remain_distinct(self):
        for status in ['available','unavailable','error']:
            row=fixture(status);PREP.validate_observation(row,messages(row))

    def test_wrong_basic_answer_or_bool_cannot_qualify(self):
        for value in [True,41,None,'42']:
            row=fixture();row['baseJS']=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_available_requires_actual_numeric42(self):
        for value in [None,True,'42',41]:
            row=fixture();row['wasmAnswer']=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_error_cannot_be_relabelled_as_missing_global(self):
        row=fixture('error');row['wasmStatus']='unavailable'
        with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_wrong_module_identity_refuses(self):
        row=fixture();row['moduleHex']=PREP.WASM_HEX[:-2]+'00'
        with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_error_requires_precise_bounded_phase_and_message(self):
        for key,value in [('errorPhase','unknown'),('errorName',None),('errorMessage','x'*513)]:
            row=fixture('error');row[key]=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_unknown_or_wrong_answer_status_refuses(self):
        for value in ['wrong-answer','passed',None]:
            row=fixture();row['wasmStatus']=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_missing_duplicate_or_wrong_request_record_refuses(self):
        row=fixture()
        for actual in [messages(row)[1:],messages(row)+[messages(row)[0]],
                       [messages(row)[0].replace('"request_id": 2','"request_id": 3'),messages(row)[1]]]:
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,actual)

    def test_missing_unbounded_or_changed_factory_refuses(self):
        row=fixture()
        for actual in [messages(row)[:1],[messages(row)[0],'QL_JSC_PROBE factory id=2 bytes=16385'],
                       messages(row)+['QL_JSC_PROBE factory id=2 bytes=1001']]:
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,actual)

    def test_unknown_nonfinite_or_reversed_observation_refuses(self):
        for key,value in [('started_uptime',True),('observed_uptime',float('nan')),
                          ('observed_uptime',99),('wasmType','invented')]:
            row=fixture();row[key]=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_added_network_jit_or_private_provider_authority_refuses(self):
        expected={'com.apple.security.app-sandbox':True,'com.apple.security.files.user-selected.read-only':True}
        PREP.validate_provider_entitlements(expected)
        for key in ['com.apple.security.network.client','com.apple.security.cs.allow-jit','com.apple.security.get-task-allow']:
            with self.assertRaises(AssertionError):PREP.validate_provider_entitlements(dict(expected,**{key:True}))

    def test_optimized_preparation_refuses_before_any_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'must-not-exist'
            result=subprocess.run([sys.executable,'-O',str(HERE/'prepare-quicklook-jsc-probe.py'),str(target)],capture_output=True,text=True,timeout=10)
            self.assertNotEqual(result.returncode,0);self.assertIn('Optimized Python cannot enforce',result.stderr)
            self.assertFalse(target.exists())


if __name__=='__main__':unittest.main()

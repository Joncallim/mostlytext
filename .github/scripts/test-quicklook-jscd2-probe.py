#!/usr/bin/env python3
"""Pure evidence corruption controls; never execute an engine locally."""
import hashlib
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('jscd2',HERE/'prepare-quicklook-jscd2-probe.py')
PREP=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(PREP)


def fixture():
    svg='<svg xmlns="http://www.w3.org/2000/svg"><rect/><text>JSC_D2_ALPHA JSC_D2_BETA</text></svg>'
    return {'kind':'mostlytext-qljscd2-compatibility','request_id':2,'started_uptime':100.0,'observed_uptime':100.1,
            'svg':svg,'svg_bytes':len(svg.encode()),'svg_sha256':hashlib.sha256(svg.encode()).hexdigest(),
            'controls':{'utf8':True,'base64':True,'randomBytes':32,'timer':True},
            'assets':dict.fromkeys(['host','d2-browser','control'],'a'*64),
            'worker_transform':dict.fromkeys(['original_sha256','transformed_sha256'],'b'*64),
            'diagnostic_only':True,'qualification_candidate':False}


def messages(row):
    raw=json.dumps(row).encode();parts=[raw[i:i+768] for i in range(0,len(raw),768)]
    return [f'QL_JSCD2_PROBE chunk id=2 index={i} count={len(parts)} base64='+base64.b64encode(v).decode() for i,v in enumerate(parts)]+[f'QL_JSCD2_PROBE result id=2 bytes={len(raw)} sha256='+hashlib.sha256(raw).hexdigest(),'QL_JSCD2_PROBE factory id=2 bytes=1000']



class D2CompatibilityTests(unittest.TestCase):
    def test_valid_schema_is_only_schema(self):
        row=fixture();PREP.validate_observation(row,messages(row))

    def test_cannot_relabel_qualification(self):
        for key,value in [('diagnostic_only',False),('qualification_candidate',True),('request_id',True),('kind','other')]:
            row=fixture();row[key]=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_missing_actual_label_or_geometry_refuses(self):
        for text in ['JSC_D2_ALPHA','JSC_D2_BETA','<rect/>']:
            row=fixture();row['svg']=row['svg'].replace(text,'')
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_active_or_remote_svg_refuses(self):
        for text in ['<script/>','<foreignObject/>','<image href="https://example.test/a"/>','<style>@import "x"</style>','<style>rect{fill:url(https://example.test/a)}</style>']:
            row=fixture();row['svg']+=text
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_wrong_svg_length_or_hash_refuses(self):
        for key,value in [('svg_bytes',True),('svg_bytes',1),('svg_sha256','a'*64)]:
            row=fixture();row[key]=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_svg_budget_refuses(self):
        row=fixture();row['svg']+='x'*65536
        with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_missing_host_controls_refuse(self):
        for key in ['utf8','base64','randomBytes','timer']:
            row=fixture();del row['controls'][key]
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_asset_or_transform_identity_refuses(self):
        for key in ['assets','worker_transform']:
            row=fixture();row[key][next(iter(row[key]))]='unknown'
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_missing_duplicate_or_different_result_refuses(self):
        row=fixture()
        for actual in [messages(row)[1:],messages(row)+[messages(row)[0]],[x.replace('id=2','id=3') for x in messages(row)]]:
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,actual)

    def test_chunk_corruption_or_wrong_hash_refuses(self):
        row=fixture();actual=messages(row)
        for changed in [[actual[0].replace('index=0','index=1')]+actual[1:],
                        [actual[0].replace('count='+str(len(actual)-2),'count=999')]+actual[1:],
                        actual[:-2]+[actual[-2].replace('sha256=','sha256=f')]+actual[-1:]]:
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,changed)

    def test_factory_required_and_frozen(self):
        row=fixture()
        for actual in [messages(row)[:-1],messages(row)+['QL_JSCD2_PROBE factory id=2 bytes=1001']]:
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,actual)

    def test_nonfinite_reversed_or_bool_time_refuses(self):
        for key,value in [('started_uptime',True),('observed_uptime',float('nan')),('observed_uptime',99)]:
            row=fixture();row[key]=value
            with self.assertRaises(RuntimeError):PREP.validate_observation(row,messages(row))

    def test_added_authority_refuses(self):
        expected={'com.apple.security.app-sandbox':True,'com.apple.security.files.user-selected.read-only':True}
        PREP.validate_provider_entitlements(expected)
        for key in ['com.apple.security.network.client','com.apple.security.cs.allow-jit','com.apple.security.get-task-allow']:
            with self.assertRaises(AssertionError):PREP.validate_provider_entitlements(dict(expected,**{key:True}))

    def test_optimized_python_refuses_before_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'must-not-exist'
            result=subprocess.run([sys.executable,'-O',str(HERE/'prepare-quicklook-jscd2-probe.py'),str(target)],capture_output=True,text=True,timeout=10)
            self.assertNotEqual(result.returncode,0);self.assertIn('Optimized Python cannot enforce',result.stderr);self.assertFalse(target.exists())


if __name__=='__main__':unittest.main()

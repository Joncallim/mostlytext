#!/usr/bin/env python3
"""Pure adversarial controls for distinct actual renderer/reply/visible-window events."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import tempfile
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


class ExecutionInputInventoryTests(unittest.TestCase):
    def fixture(self, root):
        release=root/'build/Build/Products/Release'
        app=release/'QLReplyProbeContainer.app'
        provider=app/'Contents/PlugIns/QLReplyProbeProvider.appex'
        runner=release/'QLReplyProbeFinderTests-Runner.app'
        test=runner/'Contents/PlugIns/QLReplyProbeFinderTests.xctest'
        host=release/'QLReplyProbeAutomationHost.app'
        for base,name in [(app,'QLReplyProbeContainer'),(provider,'QLReplyProbeProvider'),
                          (runner,'QLReplyProbeFinderTests-Runner'),(test,'QLReplyProbeFinderTests'),
                          (host,'QLReplyProbeAutomationHost')]:
            (base/'Contents/MacOS').mkdir(parents=True)
            (base/'Contents/MacOS'/name).write_bytes(('pure fake bytes '+name).encode())
            (base/'Contents/Info.plist').write_bytes(b'pure metadata bytes')
        project=root/'fixture/QuickLookReplyProbe.xcodeproj/project.pbxproj'
        project.parent.mkdir(parents=True);project.write_bytes(b'pure generated-project bytes')
        (release.parent/'probe.xctestrun').write_bytes(b'pure execution-plan bytes')
        (root/'observer-control').write_bytes(b'pure console bytes')
        (root/'gate-controls').write_bytes(b'pure gate-console bytes')
        resource=provider/'Contents/Resources/probe.txt';resource.parent.mkdir();resource.write_bytes(b'first resource')
        return host,resource

    def test_changed_automation_host_is_an_actual_changed_execution_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);host,_=self.fixture(root)
            first=PREP.capture_compiled(root)
            (host/'Contents/MacOS/QLReplyProbeAutomationHost').write_bytes(b'changed actual host bytes')
            self.assertNotEqual(first,PREP.capture_compiled(root))

    def test_changed_resource_is_an_actual_changed_execution_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);_,resource=self.fixture(root)
            first=PREP.capture_compiled(root);resource.write_bytes(b'changed resource')
            self.assertNotEqual(first,PREP.capture_compiled(root))

    def test_missing_automation_host_refuses_instead_of_silently_omitting(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);host,_=self.fixture(root)
            (host/'Contents/Info.plist').unlink()
            with self.assertRaises(RuntimeError):PREP.capture_compiled(root)

    def test_original_roles_and_every_actual_blob_remain_exact(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);self.fixture(root);actual=PREP.capture_compiled(root)
            self.assertTrue({'app','app_info','provider','provider_info','runner','runner_info',
                             'test','test_info','xctestrun','generated_project','observer_control'} <= actual.keys())
            for row in actual.values():
                raw=Path(row['path']).read_bytes()
                self.assertEqual(len(raw),row['bytes'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(),row['sha256'])
                self.assertEqual((root/row['blob']).read_bytes(),raw)


class PreliminaryExecutionInputTests(unittest.TestCase):
    def test_product_bytes_are_retained_without_falsely_admitting_missing_helpers(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);ExecutionInputInventoryTests.fixture(self,root)
            (root/'observer-control').unlink();(root/'gate-controls').unlink()
            preliminary=PREP.capture_compiled(root,include_helpers=False)
            self.assertNotIn('gate_controls',preliminary)
            self.assertIn('bundle:QLReplyProbeAutomationHost.app/Contents/MacOS/QLReplyProbeAutomationHost',preliminary)
            with self.assertRaises(FileNotFoundError):PREP.capture_compiled(root)


if __name__=='__main__':unittest.main()

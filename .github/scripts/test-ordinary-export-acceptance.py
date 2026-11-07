#!/usr/bin/env python3
"""Pure temporary-byte/oracle and actual non-host guard controls; never launch native code."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
sys.dont_write_bytecode=True


def load(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


PREP=load('prepare-ordinary-export-acceptance')
RUN=load('run-ordinary-export-acceptance')
VALID=b'<!doctype html><html><body><h1>NATIVE_EXPORT_CANARY</h1><p>A caf\xc3\xa9 <strong>bold</strong> and <code>code</code>.</p><table><tr><th>Key</th><th>Value</th></tr><tr><td>alpha</td><td>beta</td></tr></table></body></html>'


class ActualByteAndGuardControls(unittest.TestCase):
    def test_real_temporary_compiled_inventory_and_post_capture_corruption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            for relative in ['app/Build/Products/Release/MacDown2.app','control/Build/Products/Release/HostedFocusControl.app','control/Build/Products/Release/HostedFocusDriverTests-Runner.app']:
                bundle=root/relative;(bundle/'Contents/MacOS').mkdir(parents=True)
                (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ActualTempExecutable'}))
                (bundle/'Contents/MacOS/ActualTempExecutable').write_bytes(b'actual temporary compiled-control bytes')
                (bundle/'Contents/Resources').mkdir();(bundle/'Contents/Resources/resource.bin').write_bytes(b'actual resource bytes')
            paths=['control/Build/Products/Release/HostedFocusDriverTests-Runner.app/Contents/PlugIns/HostedFocusDriverTests.xctest/Contents/MacOS/HostedFocusDriverTests','normal-app-host','host-facts','validate-export-pdf','control/Build/Products/actual.xctestrun','fixture/HostedPublicFocus.xcodeproj/project.pbxproj','root-build-settings.json']
            for relative in paths:
                path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(relative.encode())
            before=PREP.capture(root)
            self.assertTrue(any('MacDown2.app/Contents/Resources/resource.bin' in key for key in before))
            for row in before.values():
                self.assertEqual((root/row['blob']).read_bytes(),Path(row['path']).read_bytes())
            resource=root/'app/Build/Products/Release/MacDown2.app/Contents/Resources/resource.bin'
            resource.write_bytes(b'changed after seal')
            self.assertNotEqual(PREP.capture(root),before)
            executable=root/'control/Build/Products/Release/HostedFocusControl.app/Contents/MacOS/ActualTempExecutable'
            executable.unlink()
            with self.assertRaises(RuntimeError):PREP.capture(root)

    def test_valid_html_uses_actual_structure_and_utf8(self):
        self.assertTrue(RUN.validate_html(VALID)['actual_heading_emphasis_code_and_GFM_table'])

    def test_plain_source_is_not_an_html_export(self):
        with self.assertRaises(RuntimeError):RUN.validate_html(PREP.SOURCE)

    def test_table_looking_plain_text_is_refused(self):
        with self.assertRaises(RuntimeError):RUN.validate_html(VALID.replace(b'<table>',b'<div>').replace(b'</table>',b'</div>').replace(b'<th>',b'<span>').replace(b'</th>',b'</span>').replace(b'<td>',b'<span>').replace(b'</td>',b'</span>'))

    def test_missing_canary_refused(self):
        with self.assertRaises(RuntimeError):RUN.validate_html(VALID.replace(b'NATIVE_EXPORT_CANARY',b'other'))

    def test_utf8_loss_refused(self):
        with self.assertRaises(RuntimeError):RUN.validate_html(VALID.replace(b'caf\xc3\xa9',b'cafe'))

    def test_invalid_utf8_refused(self):
        with self.assertRaises(UnicodeDecodeError):RUN.validate_html(VALID+b'\xff')

    def test_ordinary_release_build_settings_and_injected_flag_refusal(self):
        row={'target':'MacDown2','buildSettings':{'CONFIGURATION':'Release','PRODUCT_BUNDLE_IDENTIFIER':'app.mostlytext.MostlyText','ONLY_ACTIVE_ARCH':'YES','ARCHS':'arm64','SWIFT_ACTIVE_COMPILATION_CONDITIONS':''}}
        PREP.validate_settings([row])
        for key,value in [('CONFIGURATION','Debug'),('PRODUCT_BUNDLE_IDENTIFIER','other'),('ONLY_ACTIVE_ARCH','NO'),('ARCHS','x86_64'),('SWIFT_ACTIVE_COMPILATION_CONDITIONS','RELEASE_PREVIEW_PROBE')]:
            changed=json.loads(json.dumps(row));changed['buildSettings'][key]=value
            with self.assertRaises(RuntimeError):PREP.validate_settings([changed])

    def test_normal_and_optimized_nonhost_refuse_before_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)/'never-created'
            for script in ['prepare-ordinary-export-acceptance.py','run-ordinary-export-acceptance.py']:
                for flags in [[],['-O']]:
                    environment=dict(os.environ,GITHUB_ACTIONS='false')
                    result=subprocess.run([sys.executable,*flags,str(Path(__file__).with_name(script)),str(root)],env=environment,capture_output=True,timeout=15)
                    self.assertNotEqual(result.returncode,0)
                    self.assertFalse(root.exists())


if __name__=='__main__':unittest.main()

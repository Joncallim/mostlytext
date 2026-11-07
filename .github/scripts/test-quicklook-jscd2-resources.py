#!/usr/bin/env python3
"""Actual temporary-file capture regressions; no app or engine executes."""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
sys.dont_write_bytecode=True
TARGET=Path(sys.argv.pop(1)) if len(sys.argv)>1 else Path(__file__).with_name('prepare-quicklook-jscd2-probe.py')
SPEC=importlib.util.spec_from_file_location('resource_preparation',TARGET)
PREP=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(PREP)
NAMES=['host.js','control.js','d2-browser.js','D2-LICENSE.txt','D2-NOTICE.txt','THIRD_PARTY_NOTICES.md']


class RequiredProviderResourceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.release=self.root/'build/Build/Products/Release'
        self.provider=self.release/'QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex'
        self.resources=self.provider/'Contents/Resources'
        paths=['observer-control','fixture/QuickLookReplyProbe.xcodeproj/project.pbxproj',
               'build/Build/Products/probe.xctestrun']
        for bundle,exe in [('QLReplyProbeContainer.app','QLReplyProbeContainer'),
                           ('QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex','QLReplyProbeProvider'),
                           ('QLReplyProbeFinderTests-Runner.app','QLReplyProbeFinderTests-Runner'),
                           ('QLReplyProbeFinderTests-Runner.app/Contents/PlugIns/QLReplyProbeFinderTests.xctest','QLReplyProbeFinderTests'),
                           ('QLReplyProbeAutomationHost.app','QLReplyProbeAutomationHost')]:
            paths += ['build/Build/Products/Release/'+bundle+'/Contents/'+p for p in ['Info.plist','MacOS/'+exe]]
        for relative in paths:
            p=self.root/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(('actual-temp-'+relative).encode())
        self.resources.mkdir(parents=True)
        for name in NAMES:
            p=self.root/'fixture/Resources'/name;p.parent.mkdir(exist_ok=True);p.write_bytes(('exact-generated-'+name).encode())
            shutil.copyfile(p,self.resources/name)

    def test_all_required_actual_resource_bytes_are_captured(self):
        result=PREP.capture_compiled(self.root)
        for name in NAMES:self.assertTrue(any(key.endswith('/Contents/Resources/'+name) for key in result))

    def test_missing_actual_engine_refuses_before_capture(self):
        (self.resources/'d2-browser.js').unlink()
        with self.assertRaises(RuntimeError):PREP.capture_compiled(self.root)

    def test_changed_actual_host_refuses(self):
        (self.resources/'host.js').write_bytes(b'changed-host')
        with self.assertRaises(RuntimeError):PREP.capture_compiled(self.root)

    def test_symlinked_actual_resource_refuses_even_with_equal_bytes(self):
        p=self.resources/'control.js';p.unlink();p.symlink_to(self.root/'fixture/Resources/control.js')
        with self.assertRaises(RuntimeError):PREP.capture_compiled(self.root)

    def test_notice_replacement_after_capture_refuses(self):
        PREP.capture_compiled(self.root)
        (self.resources/'D2-NOTICE.txt').write_bytes(b'changed-after-seal')
        with self.assertRaises(RuntimeError):PREP.capture_compiled(self.root)


if __name__=='__main__':unittest.main()

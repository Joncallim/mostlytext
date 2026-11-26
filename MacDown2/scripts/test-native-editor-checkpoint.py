#!/usr/bin/env python3
"""Regression checks for protected checkpoint product manifests."""

import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('native-editor-checkpoint.py')
SPEC = importlib.util.spec_from_file_location('native_editor_checkpoint', SCRIPT)
CHECKPOINT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKPOINT)


class ProductManifestTests(unittest.TestCase):
    def test_internal_link_under_macos_tmp_alias_is_accepted(self):
        with tempfile.TemporaryDirectory(prefix='mostlytext-manifest-', dir='/tmp') as directory:
            root = Path(directory)
            self.assertNotEqual(root, root.resolve(strict=True))
            (root / 'internal.txt').write_text('fixture')
            (root / 'internal-link').symlink_to(root / 'internal.txt')

            manifest = CHECKPOINT.tree_manifest(root)

            self.assertEqual(manifest['internal-link'],
                             {'type': 'link', 'target': str(root / 'internal.txt')})

    def test_external_link_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='mostlytext-manifest-', dir='/tmp') as directory:
            root = Path(directory)
            with tempfile.TemporaryDirectory(prefix='mostlytext-external-', dir='/tmp') as outside:
                (Path(outside) / 'outside.txt').write_text('outside')
                (root / 'external-link').symlink_to(Path(outside) / 'outside.txt')

                with self.assertRaisesRegex(RuntimeError, 'product link escapes: external-link'):
                    CHECKPOINT.tree_manifest(root)


class TestPlanTests(unittest.TestCase):
    def test_selected_hosts_must_be_the_verified_products(self):
        plan = {
            'MacDown2Tests': {
                'TestHostPath': '__TESTROOT__/Release/MacDown2.app',
                'TestBundlePath': '__TESTHOST__/Contents/PlugIns/MacDown2Tests.xctest',
            },
            'MacDown2UITests': {
                'TestHostPath': '__TESTROOT__/Release/MacDown2UITests-Runner.app',
                'TestBundlePath': '__TESTHOST__/Contents/PlugIns/MacDown2UITests.xctest',
                'UITargetAppPath': '__TESTROOT__/Release/MacDown2.app',
            },
        }
        with tempfile.TemporaryDirectory(prefix='mostlytext-plan-', dir='/tmp') as directory:
            path = Path(directory) / 'plan.xctestrun'
            path.write_bytes(plistlib.dumps(plan))
            CHECKPOINT.verify_test_plan(path)

            for target, key in (('MacDown2Tests', 'TestHostPath'),
                                ('MacDown2UITests', 'TestHostPath'),
                                ('MacDown2UITests', 'UITargetAppPath')):
                with self.subTest(target=target, key=key):
                    original = plan[target][key]
                    plan[target][key] = '__TESTROOT__/Release/Unverified.app'
                    path.write_bytes(plistlib.dumps(plan))
                    with self.assertRaisesRegex(RuntimeError, 'unverified test product path'):
                        CHECKPOINT.verify_test_plan(path)
                    plan[target][key] = original


if __name__ == '__main__':
    unittest.main()

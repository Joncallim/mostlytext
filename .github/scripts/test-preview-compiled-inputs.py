#!/usr/bin/env python3
"""Real filesystem controls for phase-bound compiled byte evidence only."""
import copy
import json
import os
import plistlib
from pathlib import Path
import tempfile
import unittest

from preview_compiled_inputs import capture, read_regular, require_owned_phase, verify

ACTUAL_PLAN = Path(__file__).resolve().parents[2] / 'planning/downstream/evidence/actual-app-hosted-plan-2026-11-07/MacDown2_macosx26.0-arm64.xctestrun'


class CompiledInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mostlytext-preview-compiled-')
        self.root = Path(self.temp.name).resolve()
        self.products = self.root / 'products'
        self.project = self.root / 'MacDown2.xcodeproj'
        self.archive = self.root / 'evidence'
        for path, data in {
            self.products / 'Debug/MacDown2.app/Contents/MacOS/MacDown2': b'actual fixture app bytes',
            self.products / 'Debug/MacDown2.app/Contents/MacOS/MacDown2.debug.dylib': b'actual fixture Debug app code',
            self.products / 'Debug/MacDown2.app/Contents/MacOS/__preview.dylib': b'actual fixture Debug preview code',
            self.products / 'Debug/MacDown2.app/Contents/Info.plist': plistlib.dumps({
                'CFBundleIdentifier': 'app.mostlytext.MostlyText', 'CFBundleExecutable': 'MacDown2'}),
            self.products / 'Debug/MacDown2.app/Contents/PlugIns/MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests': b'actual fixture tests',
            self.products / 'MacDown2.xctestrun': ACTUAL_PLAN.read_bytes(),
            self.project / 'project.pbxproj': b'actual fixture generated project',
        }.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def tearDown(self):
        self.temp.cleanup()

    def bind(self, phase='initial'):
        return capture(self.archive, self.products, 'Debug', self.project, phase)

    def test_exact_capture_downloaded_bytes_and_phase_dedup(self):
        binding = self.bind()
        self.assertTrue(verify(self.archive, binding))
        first = sorted(p.name for p in (self.archive / 'compiled-inputs/blobs').iterdir())
        other = self.bind('selection')
        self.assertTrue(verify(self.archive, other))
        self.assertEqual(first, sorted(p.name for p in (self.archive / 'compiled-inputs/blobs').iterdir()))
        self.assertEqual(json.loads((self.archive / 'compiled-initial.json').read_text()), binding)
        with self.assertRaises(RuntimeError):
            self.bind()

    def test_actual_app_and_archive_changes_refuse_and_exact_restoration_recovers(self):
        binding = self.bind()
        for role in binding['inputs']:
            row = binding['inputs'][role]
            for path in [Path(row['path']), self.archive / row['blob']]:
                before = path.read_bytes()
                path.write_bytes(before + b'changed')
                with self.assertRaises(RuntimeError):
                    verify(self.archive, binding)
                path.write_bytes(before)
                self.assertTrue(verify(self.archive, binding))

    def test_actual_debug_code_images_are_required_physical_and_not_detached(self):
        for role, name in [('app_debug_dylib', 'MacDown2.debug.dylib'), ('app_preview_dylib', '__preview.dylib')]:
            path = self.products / 'Debug/MacDown2.app/Contents/MacOS' / name
            raw = path.read_bytes()
            path.unlink()
            with self.assertRaises(RuntimeError):
                self.bind()
            real = self.root / name
            real.write_bytes(raw)
            path.symlink_to(real)
            with self.assertRaises(RuntimeError):
                self.bind()
            path.unlink()
            path.write_bytes(raw)
        binding = self.bind()
        self.assertEqual(set(binding['inputs']), {'app_executable', 'app_info', 'test_executable',
                         'xctestrun', 'generated_project', 'app_debug_dylib', 'app_preview_dylib'})
        # Existing all-input mutation controls also mutate both actual code libraries.
        for role in ['app_debug_dylib', 'app_preview_dylib']:
            changed = copy.deepcopy(binding)
            changed['inputs'].pop(role)
            with self.assertRaises(RuntimeError):
                verify(self.archive, changed)

    def test_release_uses_its_original_five_inputs_and_refuses_debug_images(self):
        folder = self.products / 'Debug'
        release = self.products / 'Release'
        folder.rename(release)
        for name in ['MacDown2.debug.dylib', '__preview.dylib']:
            (release / 'MacDown2.app/Contents/MacOS' / name).unlink()
        run = self.products / 'MacDown2.xctestrun'
        plan = plistlib.loads(run.read_bytes())
        plan['MacDown2Tests']['TestHostPath'] = '__TESTROOT__/Release/MacDown2.app'
        run.write_bytes(plistlib.dumps(plan))
        binding = capture(self.archive, self.products, 'Release', self.project, 'initial')
        self.assertEqual(len(binding['inputs']), 5)
        self.assertTrue(verify(self.archive, binding))
        (release / 'MacDown2.app/Contents/MacOS/MacDown2.debug.dylib').write_bytes(b'unexpected code image')
        with self.assertRaises(RuntimeError):
            capture(self.archive, self.products, 'Release', self.project, 'selection')

    def test_missing_ambiguous_and_linked_compiled_inputs_refuse(self):
        test = self.products / 'Debug/MacDown2.app/Contents/PlugIns/MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests'
        data = test.read_bytes()
        test.unlink()
        with self.assertRaises(RuntimeError):
            self.bind()
        test.write_bytes(data)
        other = self.products / 'Other.xctestrun'
        other.write_bytes(b'unknown')
        with self.assertRaises(RuntimeError):
            self.bind()
        other.unlink()
        real = self.root / 'real-tests'
        test.rename(real)
        test.symlink_to(real)
        with self.assertRaises(RuntimeError):
            self.bind()
        test.unlink()
        os.link(real, test)
        with self.assertRaises(RuntimeError):
            self.bind()

    def test_retargeted_phase_inventory_and_blob_path_refuse(self):
        binding = self.bind()
        for alteration in ['phase', 'valid-other-phase', 'inventory', 'path']:
            changed = copy.deepcopy(binding)
            if alteration == 'phase':
                changed['phase'] = '../arbitrary'
            elif alteration == 'valid-other-phase':
                changed['phase'] = 'selection'
            elif alteration == 'inventory':
                changed['inputs'].pop('test_executable')
            else:
                changed['inputs']['app_info']['blob'] = '../outside'
            with self.assertRaises(RuntimeError):
                verify(self.archive, changed)
        with self.assertRaises(RuntimeError):
            self.bind('../arbitrary')

    def test_real_run_metadata_redirects_and_wrong_app_identity_refuse(self):
        path = self.products / 'MacDown2.xctestrun'
        original = path.read_bytes()
        for key, value in [('TestHostPath', '__TESTROOT__/Release/Other.app'),
                           ('TestBundlePath', '__TESTHOST__/Other.xctest'),
                           ('TestHostBundleIdentifier', 'other.application'),
                           ('ProductModuleName', 'OtherTests'), ('IsAppHostedTestBundle', False)]:
            plan = plistlib.loads(original)
            plan['MacDown2Tests'][key] = value
            path.write_bytes(plistlib.dumps(plan))
            with self.assertRaises(RuntimeError):
                self.bind()
        path.write_bytes(original)
        info = self.products / 'Debug/MacDown2.app/Contents/Info.plist'
        for key in ['CFBundleIdentifier', 'CFBundleExecutable']:
            value = {'CFBundleIdentifier': 'app.mostlytext.MostlyText', 'CFBundleExecutable': 'MacDown2'}
            value[key] = 'Other'
            info.write_bytes(plistlib.dumps(value))
            with self.assertRaises(RuntimeError):
                self.bind()

    def test_owned_app_path_checkout_and_digest_must_all_match(self):
        binding = self.bind()
        app = binding['inputs']['app_executable']
        identity = {'app': app['path'], 'app_sha256': app['sha256'], 'checkout': '0' * 40}
        require_owned_phase(identity, binding, '0' * 40)
        for key in ['app', 'app_sha256', 'checkout']:
            changed = dict(identity)
            changed[key] = 'different'
            with self.assertRaises(RuntimeError):
                require_owned_phase(changed, binding, '0' * 40)

    def test_detached_test_binary_refuses_even_when_it_is_unique(self):
        source = self.products / 'Debug/MacDown2.app/Contents/PlugIns/MacDown2Tests.xctest'
        source.rename(self.products / 'Debug/MacDown2Tests.xctest')
        with self.assertRaises(RuntimeError):
            self.bind()


if __name__ == '__main__':
    unittest.main()

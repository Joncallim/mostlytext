#!/usr/bin/env python3
"""Real filesystem controls for phase-bound compiled byte evidence only."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest

from preview_compiled_inputs import capture, read_regular, verify


class CompiledInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mostlytext-preview-compiled-')
        self.root = Path(self.temp.name).resolve()
        self.products = self.root / 'products'
        self.project = self.root / 'MacDown2.xcodeproj'
        self.archive = self.root / 'evidence'
        for path, data in {
            self.products / 'Debug/MacDown2.app/Contents/MacOS/MacDown2': b'actual fixture app bytes',
            self.products / 'Debug/MacDown2.app/Contents/Info.plist': b'actual fixture metadata',
            self.products / 'Debug/MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests': b'actual fixture tests',
            self.products / 'MacDown2.xctestrun': b'actual fixture selected run',
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

    def test_missing_ambiguous_and_linked_compiled_inputs_refuse(self):
        test = self.products / 'Debug/MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests'
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


if __name__ == '__main__':
    unittest.main()

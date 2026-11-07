#!/usr/bin/env python3
"""Real-filesystem and admission controls; no app/native framework executes."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from hosted_cli_stdin_contract import capture, read_regular, require_ui, verify


class CompiledEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='mostlytext-stdin-contract-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / 'actual-driver'
        self.source.write_bytes(b'actual compiled input fixture')
        self.paths = {'driver': self.source}

    def test_actual_capture_and_original_bytes_verify(self):
        rows = capture(self.root, self.paths)
        self.assertEqual(verify(self.root, self.paths), rows)
        self.assertEqual(read_regular(self.root / rows['driver']['blob']), self.source.read_bytes())

    def test_changed_compiled_input_is_refused(self):
        capture(self.root, self.paths)
        self.source.write_bytes(b'replaced compiled input')
        with self.assertRaises(RuntimeError):
            verify(self.root, self.paths)

    def test_changed_downloaded_blob_is_refused(self):
        rows = capture(self.root, self.paths)
        (self.root / rows['driver']['blob']).write_bytes(b'replaced archive')
        with self.assertRaises(RuntimeError):
            verify(self.root, self.paths)

    def test_symlink_input_is_refused(self):
        linked = self.root / 'symlink'
        linked.symlink_to(self.source)
        with self.assertRaises(RuntimeError):
            read_regular(linked)

    def test_hardlinked_input_is_refused(self):
        os.link(self.source, self.root / 'other-name')
        with self.assertRaises(RuntimeError):
            read_regular(self.source)

    def test_retargeted_path_is_refused(self):
        rows = capture(self.root, self.paths)
        alternate = self.root / 'alternate'
        alternate.write_bytes(self.source.read_bytes())
        with self.assertRaises(RuntimeError):
            verify(self.root, {'driver': alternate})
        rows['driver']['blob'] = '../unowned'
        (self.root / 'cli-compiled.json').write_text(json.dumps(rows))
        with self.assertRaises(RuntimeError):
            verify(self.root, self.paths)

    def test_omitted_compiled_role_is_refused(self):
        capture(self.root, self.paths)
        with self.assertRaises(RuntimeError):
            verify(self.root, {})

    def test_recapture_cannot_replace_first_manifest(self):
        capture(self.root, self.paths)
        original = (self.root / 'cli-compiled.json').read_bytes()
        with self.assertRaises(RuntimeError):
            capture(self.root, self.paths)
        self.assertEqual((self.root / 'cli-compiled.json').read_bytes(), original)


class ActualResultTests(unittest.TestCase):
    def test_complete_actual_pass_is_required(self):
        summary = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0,
                   'skippedTests': 0, 'expectedFailures': 0}
        owned = {'returncode': 0, 'timed_out': False, 'cancelled': False, 'app_cleanup_requested': []}
        require_ui(summary, owned, 0)
        for key in summary:
            changed = copy.deepcopy(summary)
            changed[key] = not changed[key]
            with self.subTest(boolean=key), self.assertRaises(RuntimeError):
                require_ui(changed, owned, 0)
        for key in ['failedTests', 'skippedTests', 'expectedFailures']:
            changed = dict(summary, **{key: 1})
            with self.subTest(failure=key), self.assertRaises(RuntimeError):
                require_ui(changed, owned, 0)
        for key, value in [('returncode', False), ('returncode', 65), ('timed_out', True), ('cancelled', True), ('app_cleanup_requested', [12])]:
            with self.subTest(owned=key), self.assertRaises(RuntimeError):
                require_ui(summary, dict(owned, **{key: value}), 0)
        with self.assertRaises(RuntimeError):
            require_ui(summary, owned, 65)


class HostAdmissionTests(unittest.TestCase):
    def test_real_normal_and_optimized_foreign_host_refuse_before_writes(self):
        script = Path(__file__).with_name('prepare-hosted-cli-stdin-save.py').resolve()
        with tempfile.TemporaryDirectory(prefix='mostlytext-stdin-admit-') as directory:
            root = Path(directory) / 'not-created'
            environment = dict(os.environ, GITHUB_ACTIONS='false')
            for flags in [[], ['-O']]:
                result = subprocess.run([sys.executable, *flags, str(script), str(root), '--phase', 'prepare'],
                                        env=environment, capture_output=True, text=True, timeout=15)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(root.exists())
                self.assertIn('Optimized Python' if flags else 'AssertionError', result.stderr)

    def test_unqualified_dependency_refuses_before_any_git_or_write(self):
        script = Path(__file__).with_name('prepare-hosted-cli-stdin-save.py').resolve()
        spec = importlib.util.spec_from_file_location('stdin_prepare_control', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        class AcceptedControlHost:
            @staticmethod
            def check_host(root):
                pass
        module.preparation_module = lambda: AcceptedControlHost
        module.QUALIFIED_PREVIEW_MAIN = 'PENDING_ACTUAL_QUALIFIED_PREVIEW_MAIN'
        original = module.subprocess.run
        try:
            module.subprocess.run = lambda *args, **kwargs: self.fail('Held execution must not invoke a subprocess')
            with self.assertRaisesRegex(RuntimeError, 'Execution held'):
                module.admit(Path('/fictional/not-created'))
        finally:
            module.subprocess.run = original


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Real filesystem, typed-state and held-host controls; never launches app code."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from migration_profile_evidence import editor_width, require_preserved, require_session, snapshot


class ProfileEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mostlytext-migration-evidence-')
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'old'
        self.source.mkdir(mode=0o700)
        (self.source / 'Recovery').mkdir(mode=0o700)
        (self.source / 'Recovery/draft').write_bytes(b'Unsaved\r\n\xe6\x96\x87\xf0\x9f\x99\x82')

    def tearDown(self):
        self.temp.cleanup()

    def test_real_bytes_identities_and_safe_preserved_copy(self):
        before = snapshot(self.source, self.root / 'before')
        again = snapshot(self.source, self.root / 'again')
        self.assertEqual(before, again)
        preserved = copy.deepcopy(before)
        for row in preserved.values():
            row['inode'] += 1
            row['mode'] = 0o700 if row['kind'] == 'directory' else 0o600
        require_preserved(before, preserved)
        preserved['Recovery/draft']['sha256'] = '0' * 64
        with self.assertRaises(RuntimeError):
            require_preserved(before, preserved)
        (self.source / 'Recovery/draft').write_bytes(b'Changed')
        self.assertNotEqual(before, snapshot(self.source, self.root / 'changed'))

    def test_missing_extra_and_unsafe_permissions_refused(self):
        before = snapshot(self.source, self.root / 'before')
        for mutated in [dict(list(before.items())[:-1]), dict(before, extra=before['Recovery/draft'])]:
            with self.assertRaises(RuntimeError):
                require_preserved(before, mutated)
        mutated = copy.deepcopy(before)
        mutated['Recovery/draft']['mode'] = 0o644
        with self.assertRaises(RuntimeError):
            require_preserved(before, mutated)

    def test_real_symbolic_hard_links_and_special_nodes_refused(self):
        file = self.source / 'Recovery/draft'
        link = self.source / 'link'
        link.symlink_to(file)
        with self.assertRaises(RuntimeError):
            snapshot(self.source, self.root / 'symlink')
        link.unlink()
        os.link(file, link)
        with self.assertRaises(RuntimeError):
            snapshot(self.source, self.root / 'hardlink')
        link.unlink()
        os.mkfifo(link)
        with self.assertRaises(RuntimeError):
            snapshot(self.source, self.root / 'fifo')

    def test_typed_canonical_indentation_rejects_wrong_encoding_and_boolean(self):
        self.assertEqual(editor_width({'appSettings.editor': b'{"indentationWidth":2}'}), 2)
        for value in ['{"indentationWidth":2}', b'{"indentationWidth":true}']:
            with self.assertRaises(RuntimeError):
                editor_width({'appSettings.editor': value})

    def test_actual_url_relocation_identity_encoding_and_epoch_controls(self):
        state = self.root / 'new/State'
        tabs = [{'id': 'external', 'fileURL': (self.root / 'external.txt').as_uri(),
                 'documentRecoveryEpoch': 'epoch1', 'baseSHA256': 'first', 'encoding': {'id': 4}},
                {'id': 'managed', 'fileURL': (self.source / 'snippets.json').as_uri(),
                 'documentRecoveryEpoch': 'epoch2', 'baseSHA256': 'second', 'encoding': {'id': 4}}]
        original = {'version': 1, 'tabs': tabs, 'activeTabID': 'managed'}
        seed = {'old': str(self.source), 'session': original}
        after = copy.deepcopy(original)
        after['tabs'][1]['fileURL'] = (state / 'snippets.json').as_uri()
        require_session(seed, after, state)
        for field, changed in [('id', 'wrong'), ('documentRecoveryEpoch', 'other'),
                               ('baseSHA256', 'wrong'), ('encoding', {'id': 5}),
                               ('fileURL', (self.source / 'snippets.json').as_uri())]:
            altered = copy.deepcopy(after)
            altered['tabs'][1][field] = changed
            with self.assertRaises(RuntimeError):
                require_session(seed, altered, state)
        for alteration in ['extra', 'active']:
            altered = copy.deepcopy(after)
            if alteration == 'extra':
                altered['tabs'].append(tabs[0])
            else:
                altered['activeTabID'] = 'external'
            with self.assertRaises(RuntimeError):
                require_session(seed, altered, state)


class AdmissionTests(unittest.TestCase):
    def test_actual_held_or_untrusted_host_precedes_receipt_and_ancestry(self):
        file = Path(__file__).with_name('prepare-hosted-migration.py')
        spec = importlib.util.spec_from_file_location('held_migration', file)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch.object(module.subprocess, 'run', side_effect=AssertionError('Ancestry reached')) as command:
            with self.assertRaises((AssertionError, RuntimeError)):
                module.admit()
            command.assert_not_called()
        # The actual host guard refuses claimed CI variables; it never reads a receipt.
        module.QUALIFIED_MAIN = '0' * 40
        with patch.object(module.subprocess, 'run', side_effect=AssertionError('Ancestry reached')) as command:
            with self.assertRaises((AssertionError, RuntimeError)):
                module.admit()
            command.assert_not_called()

    def test_optimized_execution_refuses_before_host_receipt_or_profile_access(self):
        for script, args in [('prepare-hosted-migration.py', ['prepare']), ('run-hosted-migration.py', [])]:
            result = subprocess.run([sys.executable, '-O', str(Path(__file__).with_name(script)), *args],
                                    capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Optimized Python is refused before any migration access', result.stderr)


if __name__ == '__main__':
    unittest.main()

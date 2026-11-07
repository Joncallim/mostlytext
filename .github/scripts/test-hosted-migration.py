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

from migration_profile_evidence import editor_width, require_blocked_preservation, require_preserved, require_session, sha, snapshot


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

    def test_blocked_startup_admits_private_plan_but_refuses_any_final_publication(self):
        old = snapshot(self.source, self.root / 'before')
        install = self.root / 'installation'
        install.mkdir(mode=0o700)
        (install / 'installation-plan.json').write_bytes(b'private plan')
        captured = {'trees': {'old': old, 'state': {},
                              'installation': snapshot(install, self.root / 'private')},
                    'domains': {'old': {'editor': b'original'}, 'current': None}}
        seed = {'externalSHA256': sha(b'external')}
        require_blocked_preservation(captured, captured, seed, b'external', False)
        for name in ['installation-preferences.json', 'installation-paths.json', 'installation-complete.json']:
            file = install / name
            file.write_bytes(b'published')
            changed = copy.deepcopy(captured)
            changed['trees']['installation'] = snapshot(install, self.root / name)
            with self.assertRaises(RuntimeError):
                require_blocked_preservation(captured, changed, seed, b'external', False)
            file.unlink()
        (install / 'installation-v1').mkdir()
        changed = copy.deepcopy(captured)
        changed['trees']['installation'] = snapshot(install, self.root / 'generation')
        with self.assertRaises(RuntimeError):
            require_blocked_preservation(captured, changed, seed, b'external', False)

    def test_blocked_readback_rejects_identity_domain_external_and_command_changes(self):
        old = snapshot(self.source, self.root / 'before')
        baseline = {'trees': {'old': old, 'state': {}, 'installation': {}},
                    'domains': {'old': {'editor': b'original'}, 'current': None}}
        seed = {'externalSHA256': sha(b'external')}
        for kind in ['old', 'domain', 'state']:
            changed = copy.deepcopy(baseline)
            if kind == 'old':
                changed['trees']['old']['Recovery/draft']['inode'] += 1
            elif kind == 'domain':
                changed['domains']['current'] = {'new': True}
            else:
                changed['trees']['state'] = {'.': {'kind': 'directory'}}
            with self.assertRaises(RuntimeError):
                require_blocked_preservation(baseline, changed, seed, b'external', False)
        for data, sentinel in [(b'changed', False), (b'external', True)]:
            with self.assertRaises(RuntimeError):
                require_blocked_preservation(baseline, baseline, seed, data, sentinel)


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
        for script, args in [('prepare-hosted-migration.py', ['prepare']), ('run-hosted-migration.py', []),
                             ('prepare-hosted-migration.py', ['prepare', '--future-session']),
                             ('run-hosted-migration.py', ['--future-session'])]:
            result = subprocess.run([sys.executable, '-O', str(Path(__file__).with_name(script)), *args],
                                    capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Optimized Python is refused before any migration access', result.stderr)

    def test_future_hold_precedes_host_receipt_and_ancestry(self):
        file = Path(__file__).with_name('prepare-hosted-migration.py')
        spec = importlib.util.spec_from_file_location('future_held_migration', file)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.FUTURE_QUALIFIED_MAIN = 'PENDING_CONTROL_ANCHOR'
        with patch.object(module, 'preparation', side_effect=AssertionError('Host reached')) as host:
            with self.assertRaisesRegex(RuntimeError, 'Future-session execution is held'):
                module.admit(True)
            host.assert_not_called()

    def test_receipt_scenario_or_anchor_cannot_change_before_binding_inputs(self):
        file = Path(__file__).with_name('prepare-hosted-migration.py')
        spec = importlib.util.spec_from_file_location('migration_retargeting', file)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix='mostlytext-migration-retarget-') as directory:
            module.ROOT = Path(directory)
            record = {'migration_qualified_main': module.QUALIFIED_MAIN,
                      'migration_scenario': 'future-session',
                      'migration_future_qualified_main': module.FUTURE_QUALIFIED_MAIN}
            for future, key, value in [(False, None, None), (True, 'migration_scenario', 'valid-profile'),
                                        (True, 'migration_future_qualified_main', '0' * 40)]:
                altered = dict(record)
                if key:
                    altered[key] = value
                path = module.ROOT / 'receipt.json'
                before = json.dumps(altered).encode()
                path.write_bytes(before)
                args = ['prepare-hosted-migration.py', 'verify'] + (['--future-session'] if future else [])
                with patch.object(module, 'admit', return_value=object()), patch.object(sys, 'argv', args), \
                        patch.object(module, 'verify_seed', side_effect=AssertionError('Input binding reached')) as seed:
                    with self.assertRaisesRegex(RuntimeError, 'receipt cannot be retargeted'):
                        module.main()
                    seed.assert_not_called()
                self.assertEqual(path.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()

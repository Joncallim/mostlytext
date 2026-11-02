#!/usr/bin/env python3
"""Non-launch unit controls for the fixed runner preflight."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import uuid

spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('fixed-issue88-runner-preflight.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

class FixedRunnerChecks(unittest.TestCase):
    def setUp(self):
        self.manifest = {'version':1, 'bundleID':r.BUNDLE_PREFIX + str(uuid.uuid4()),
                         'hostID':'00006030-0012446C0E83001C','ownerUID':501,'ownerHome':'/Users/owner',
                         'selectedTest':r.EXPECTED_TEST,'xctestrunSHA256':'a'*64,
                         'sourcePatchSHA256':'b'*64,
                         'sourceSHA':'f'*40, 'sourceManifestSHA256':'0'*64,
                         'binarySHA256':{'app':'c'*64,'runner':'d'*64,'test':'e'*64,'cli':'f'*64}}

    def test_exact_command_is_bounded_and_single_case(self):
        argv = r.command_for(Path('/private/tmp/isolated.xctestrun'), Path('/private/tmp/result.xcresult'), self.manifest['hostID'])
        self.assertEqual(argv.count('-only-testing:' + r.EXPECTED_TEST), 1)
        self.assertEqual(argv[argv.index('-test-timeouts-enabled') + 1], 'YES')
        self.assertEqual(argv[argv.index('-maximum-test-execution-time-allowance') + 1], '120')
        self.assertEqual(argv[argv.index('-test-iterations') + 1], '1')
        self.assertEqual(argv[argv.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertNotIn('-retry-tests-on-failure', argv)
        self.assertNotIn('-run-tests-until-failure', argv)
        self.assertTrue(r.EXECUTION_HOLD)
        with self.assertRaises(r.Refusal):
            r.command_for(Path('relative.xctestrun'), Path('/private/tmp/result'), self.manifest['hostID'])

    def test_manifest_and_exact_bindings(self):
        r.validate_manifest(self.manifest)
        actual = dict(self.manifest)
        r.check_binding(self.manifest, actual)
        for key in ['selectedTest','bundleID','xctestrunSHA256','sourcePatchSHA256','sourceSHA','sourceManifestSHA256']:
            altered = dict(actual); altered[key] = 'wrong'
            with self.assertRaises(r.Refusal): r.check_binding(self.manifest, altered)
        altered = dict(actual); altered['binarySHA256'] = dict(actual['binarySHA256'], app='f'*64)
        with self.assertRaises(r.Refusal): r.check_binding(self.manifest, altered)
        malformed = dict(self.manifest, hostID='platform=macOS')
        with self.assertRaises(r.Refusal): r.validate_manifest(malformed)

    def test_missing_or_malformed_source_identities_are_refused(self):
        for key, invalid in [('sourceSHA', ['x'*40, 'A'*40, '', None]),
                             ('sourceManifestSHA256', ['x'*64, 'A'*64, '', None])]:
            missing = dict(self.manifest); del missing[key]
            with self.assertRaises(r.Refusal): r.validate_manifest(missing)
            for value in invalid:
                malformed = dict(self.manifest); malformed[key] = value
                with self.assertRaises(r.Refusal): r.validate_manifest(malformed)

    @mock.patch.object(r.os, 'geteuid', return_value=501)
    @mock.patch.object(r.os, 'getuid', return_value=501)
    def test_owner_account_refused_before_any_gui_action(self, *_):
        with self.assertRaises(r.Refusal): r.check_account(self.manifest)

    def test_missing_or_accessible_owner_data_is_not_denial_proof(self):
        with tempfile.TemporaryDirectory(prefix='issue88-denial-') as tmp:
            existing = Path(tmp) / 'fixture'; existing.write_text('disposable')
            for path in (existing, Path(tmp) / 'missing'):
                with self.assertRaises(r.Refusal): r.check_denied([path])

    def test_product_tree_rejects_writable_ancestor_and_symlink(self):
        with tempfile.TemporaryDirectory(prefix='issue88-products-') as tmp:
            root = (Path(tmp).resolve() / 'root'); root.mkdir()
            app = root / 'app'; app.mkdir()
            binary = app / 'binary'; binary.write_text('fixture')
            with mock.patch.object(r.os, 'access', return_value=False):
                r.check_products_immutable([app], root)
                top_alias = root / 'app-alias'; top_alias.symlink_to(app, target_is_directory=True)
                with self.assertRaises(r.Refusal): r.check_products_immutable([top_alias], root)
                (app / 'link').symlink_to(binary)
                with self.assertRaises(r.Refusal): r.check_products_immutable([app], root)
            with mock.patch.object(r.os, 'access', side_effect=lambda p, _: Path(p) == root.parent):
                with self.assertRaises(r.Refusal): r.check_products_immutable([app], root)

    def test_private_scratch_and_symlink(self):
        with tempfile.TemporaryDirectory(prefix='issue88-scratch-') as tmp:
            scratch = Path(tmp).resolve()
            r.check_private_scratch(scratch)
            alias = scratch / 'alias'; alias.symlink_to(scratch, target_is_directory=True)
            with self.assertRaises(r.Refusal): r.check_private_scratch(alias)

if __name__ == '__main__': unittest.main()

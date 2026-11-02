#!/usr/bin/env python3
"""Pure negative controls; no app or UI test is launched."""
import importlib.util
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace
import uuid

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).with_name('preflight-issue88-isolation.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class GuardTests(unittest.TestCase):
    def setUp(self):
        self.bundle = p.BUNDLE_PREFIX + str(uuid.uuid4())
    def test_exact_test_and_identity(self):
        p.validate_request(self.bundle, [p.EXPECTED_TEST])
        for selected in ([], [p.EXPECTED_TEST, p.EXPECTED_TEST], ['MacDown2UITests']):
            with self.assertRaises(p.Refusal): p.validate_request(self.bundle, selected)
        for bundle in ('com.joncallim.MacDown2', p.BUNDLE_PREFIX + 'bad', p.BUNDLE_PREFIX + 'x' * 36):
            with self.assertRaises(p.Refusal): p.validate_request(bundle, [p.EXPECTED_TEST])
    def test_compiler_flags_not_just_target_or_comments(self):
        good = 'swiftc -module-name MacDown2 -D DEBUG -D UITEST_ISOLATED other'
        p.verify_flags(good, 'MacDown2')
        p.verify_flags('swiftc -module-name MacDown2 -DDEBUG -DUITEST_ISOLATED other', 'MacDown2')
        for bad in ('swiftc -module-name MacDown2 -D DEBUG other',
                    'swiftc -module-name MacDown2 -D UITEST_ISOLATED other',
                    'swiftc -module-name Other -D DEBUG -D UITEST_ISOLATED other'):
            with self.assertRaises(p.Refusal): p.verify_flags(bad, 'MacDown2')
    def test_plan_only_adds_runner_identity_and_rejects_filters(self):
        original = {'MacDown2UITests': {'EnvironmentVariables': {'TERM': 'dumb'}}, '__xctestrun_metadata__': {}}
        prepared = copy.deepcopy(original)
        prepared['MacDown2UITests']['EnvironmentVariables'].update(
            MOSTLYTEXT_UI_TEST_BUNDLE_ID=self.bundle, MOSTLYTEXT_UI_TEST_OWNER_UID='501')
        prepared['MacDown2UITests'].update(TestTimeoutsEnabled=True, DefaultTestExecutionTimeAllowance=60,
                                         MaximumTestExecutionTimeAllowance=120)
        p.validate_plan(original, prepared, self.bundle, 501)
        changed = copy.deepcopy(prepared)
        changed['MacDown2UITests']['EnvironmentVariables']['TERM'] = 'other'
        with self.assertRaises(p.Refusal): p.validate_plan(original, changed, self.bundle, 501)
        filtered = copy.deepcopy(original)
        filtered['MacDown2UITests']['SkipTestIdentifiers'] = ['x']
        prepared_filtered = copy.deepcopy(filtered)
        prepared_filtered['MacDown2UITests']['EnvironmentVariables']['MOSTLYTEXT_UI_TEST_BUNDLE_ID'] = self.bundle
        with self.assertRaises(p.Refusal): p.validate_plan(filtered, prepared_filtered, self.bundle, 501)

    def test_plan_rejects_disabled_or_extended_timeouts(self):
        original = {'MacDown2UITests': {'EnvironmentVariables': {}}, '__xctestrun_metadata__': {}}
        prepared = copy.deepcopy(original)
        prepared['MacDown2UITests'].update(
            EnvironmentVariables={'MOSTLYTEXT_UI_TEST_BUNDLE_ID': self.bundle, 'MOSTLYTEXT_UI_TEST_OWNER_UID': '501'},
            TestTimeoutsEnabled=True, DefaultTestExecutionTimeAllowance=60, MaximumTestExecutionTimeAllowance=120)
        p.validate_plan(original, prepared, self.bundle, 501)
        for key, bad in [('TestTimeoutsEnabled', False), ('DefaultTestExecutionTimeAllowance', 600),
                         ('MaximumTestExecutionTimeAllowance', 600)]:
            altered = copy.deepcopy(prepared); altered['MacDown2UITests'][key] = bad
            with self.assertRaises(p.Refusal): p.validate_plan(original, altered, self.bundle, 501)

    def test_current_plan_requires_cli_and_rejects_extra_or_escaped_products(self):
        products = [
            '__TESTROOT__/UITestIsolated/MacDown2.app',
            '__TESTROOT__/UITestIsolated/MacDown2UITests-Runner.app',
            '__TESTROOT__/UITestIsolated/MacDown2UITests-Runner.app/Contents/PlugIns/MacDown2UITests.xctest',
            '__TESTROOT__/UITestIsolated/mostlytext',
        ]
        p.validate_dependent_products({'DependentProductPaths': products})
        for changed in (products[:-1], products + ['/tmp/injected'],
                        products[:-1] + ['__TESTROOT__/../mostlytext'],
                        products + [products[-1]], list(reversed(products))):
            with self.subTest(products=changed), self.assertRaises(p.Refusal):
                p.validate_dependent_products({'DependentProductPaths': changed})
        with self.assertRaises(p.Refusal): p.validate_dependent_products({})

    def test_cli_binding_requires_identical_regular_embedded_copy(self):
        with tempfile.TemporaryDirectory(prefix='issue88-cli-') as tmp:
            products = Path(tmp).resolve()
            app = products / 'MacDown2.app'
            embedded = app / 'Contents/MacOS/mostlytext-cli'
            embedded.parent.mkdir(parents=True)
            external = products / 'mostlytext'
            external.write_bytes(b'reviewed CLI')
            embedded.write_bytes(external.read_bytes())
            self.assertEqual(p.validate_embedded_cli(products, app), external)
            embedded.write_bytes(b'different executable')
            with self.assertRaises(p.Refusal): p.validate_embedded_cli(products, app)
            embedded.unlink(); embedded.symlink_to(external)
            with self.assertRaises(p.Refusal): p.validate_embedded_cli(products, app)
            embedded.unlink(); embedded.write_bytes(external.read_bytes())
            external.unlink(); external.symlink_to(embedded)
            with self.assertRaises(p.Refusal): p.validate_embedded_cli(products, app)

    def test_environment_rejects_unexpected_injection(self):
        target = {'EnvironmentVariables': dict(p.RUNNER_ENV, MOSTLYTEXT_UI_TEST_BUNDLE_ID=self.bundle, MOSTLYTEXT_UI_TEST_OWNER_UID='501'),
                  'UITargetAppEnvironmentVariables': dict(p.APP_ENV),
                  'TestingEnvironmentVariables': dict(p.TESTING_ENV)}
        p.validate_environments(target, self.bundle, 501)
        target['UITargetAppEnvironmentVariables']['DYLD_INSERT_LIBRARIES'] = '/tmp/untrusted'
        with self.assertRaises(p.Refusal): p.validate_environments(target, self.bundle, 501)

    def test_source_manifest_rejects_changed_content_and_escape(self):
        with tempfile.TemporaryDirectory(prefix='issue88-source-') as tmp:
            root = Path(tmp); source = root / 'source'; source.mkdir()
            content = source / 'input.swift'; content.write_text('original')
            manifest = root / 'source-manifest.json'
            manifest.write_text(json.dumps({'input.swift': p.sha(content)}))
            receipt = {'sourceManifestSHA256': p.sha(manifest)}
            p.validate_source_manifest(root, receipt)
            content.write_text('changed')
            with self.assertRaises(p.Refusal): p.validate_source_manifest(root, receipt)
            content.write_text('original')
            manifest.write_text(json.dumps({'../outside': 'a' * 64}))
            with self.assertRaises(p.Refusal): p.validate_source_manifest(root, receipt)
            receipt['sourceManifestSHA256'] = p.sha(manifest)
            with self.assertRaises(p.Refusal): p.validate_source_manifest(root, receipt)

    def test_product_path_cannot_escape_via_symlink(self):
        with tempfile.TemporaryDirectory(prefix='issue88-preflight-') as tmp:
            root = Path(tmp) / 'root'; root.mkdir()
            good = root / 'product'; good.write_text('fixture')
            outside = Path(tmp) / 'outside'; outside.write_text('fixture')
            link = root / 'link'; link.symlink_to(outside)
            self.assertEqual(p.checked_path(good, root), good.resolve())
            with self.assertRaises(p.Refusal): p.checked_path(link, root)

    def test_complete_candidate_inventory_and_content(self):
        with tempfile.TemporaryDirectory(prefix='issue88-candidate-') as tmp:
            root = Path(tmp).resolve()
            # This input was outside the former six-file comparison.
            name = 'WindowCoordinator.swift'
            source = root / name; source.write_text('reviewed')
            manifest = {name: p.sha(source)}
            p.validate_candidate_sources(manifest, root, [name])
            for paths in ([], [name, 'extra.swift']):
                with self.assertRaises(p.Refusal): p.validate_candidate_sources(manifest, root, paths)
            source.write_text('changed')
            with self.assertRaises(p.Refusal): p.validate_candidate_sources(manifest, root, [name])
            source.unlink()
            with self.assertRaises(OSError): p.validate_candidate_sources(manifest, root, [name])

    def test_source_manifest_rejects_noncanonical_paths_duplicates_and_symlinks(self):
        with tempfile.TemporaryDirectory(prefix='issue88-manifest-') as tmp:
            root = Path(tmp).resolve(); source = root / 'source'; source.mkdir()
            content = source / 'input.swift'; content.write_text('original')
            manifest = root / 'source-manifest.json'
            def check(text):
                manifest.write_text(text)
                return p.validate_source_manifest(root, {'sourceManifestSHA256': p.sha(manifest)})
            for rel in ('/absolute', '', './input.swift', 'a//b', '../outside', 'a/../input.swift', 'a\\b'):
                with self.subTest(rel=rel), self.assertRaises(p.Refusal):
                    check(json.dumps({rel: 'a' * 64}))
            for digest in ('wrong', 1, 'A' * 64):
                with self.assertRaises(p.Refusal): check(json.dumps({'input.swift': digest}))
            with self.assertRaises(p.Refusal): check('{"input.swift":"' + 'a'*64 + '","input.swift":"' + 'b'*64 + '"}')
            for target in (content, root / 'outside'):
                if not target.exists(): target.write_text('original')
                alias = source / 'alias'; alias.symlink_to(target)
                with self.assertRaises(p.Refusal): check(json.dumps({'alias': p.sha(content)}))
                alias.unlink()

    def test_git_adapter_checks_commit_root_and_all_inputs(self):
        with tempfile.TemporaryDirectory(prefix='issue88-git-') as tmp:
            root = Path(tmp).resolve()
            (root / 'Package.resolved').write_text('locked')
            manifest = {'Package.resolved': p.sha(root / 'Package.resolved')}
            receipt = {'sourceSHA': 'a' * 40}
            outputs = [str(root).encode() + b'\n', b'a' * 40 + b'\n', b'Package.resolved\0']
            def run_with(values):
                return mock.patch.object(p.subprocess, 'run', side_effect=[SimpleNamespace(stdout=value) for value in values])
            with run_with(outputs) as git:
                p.validate_candidate_identity(manifest, root, receipt)
                self.assertEqual(git.call_args_list[-1].args[0][-5:],
                                 ['ls-files', '--cached', '--others', '--exclude-standard', '-z'])
            # Wrong root/commit, extra untracked input, or a missing tracked
            # lock must all fail. Generated ignored products never enter the list.
            for values in ([str(root.parent).encode()], [outputs[0], b'b'*40],
                           [*outputs[:2], b'Package.resolved\0extra.swift\0'], [*outputs[:2], b'']):
                with run_with(values), self.assertRaises(p.Refusal):
                    p.validate_candidate_identity(manifest, root, receipt)
            for value in (None, '', 'x'*40, 'A'*40):
                with self.assertRaises(p.Refusal): p.validate_candidate_identity(manifest, root, {'sourceSHA': value})

if __name__ == '__main__': unittest.main()

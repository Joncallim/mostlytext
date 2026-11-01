#!/usr/bin/env python3
"""Pure negative controls; no app or UI test is launched."""
import importlib.util
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
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

if __name__ == '__main__': unittest.main()

"""Keep complete root terms, credits and conservative provenance together."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_compiler_rt_notices as subject


class CompilerRuntimeNoticeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = Path(__file__).resolve().parents[2]
        self.report = json.loads((source / subject.MANIFEST).read_text())
        names = [subject.MANIFEST, 'compliance/inventory.json', 'compliance/generated/THIRD_PARTY_NOTICES.md',
                 'compliance/evidence/viz-js-3.30.0/source-audit.json']
        names.extend(row['path'] for row in self.report['license_texts'])
        for name in names:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, target)

    def test_complete_captured_root_terms_and_link_selection_pass(self):
        report = subject.verify_installed(self.root)
        self.assertEqual(report['source_version'], '5.0.7-git')
        self.assertEqual(len(report['inputs']), 6)
        self.assertEqual(len(report['source_anchors']), 3)

    def test_full_exception_and_legacy_conditions_cannot_be_removed(self):
        path = self.root / self.report['license_texts'][0]['path']
        original = path.read_bytes()
        for token in [b'LLVM Exceptions', b'Copyright (c) 2009-2019', b'Copyright (c) 2009-2015',
                      b'Redistributions in binary form must reproduce', b'Neither the names of the LLVM Team']:
            with self.subTest(token=token):
                self.assertIn(token, original)
                path.write_bytes(original.replace(token, b'condition removed'))
                with self.assertRaisesRegex(ValueError, 'complete compiler-runtime root text changed'):
                    subject.verify_installed(self.root)
        path.write_bytes(original)

    def test_referenced_contributor_credits_are_required(self):
        path = self.root / self.report['license_texts'][1]['path']
        path.write_bytes(path.read_bytes().replace(b'Howard Hinnant', b'Uncredited author'))
        with self.assertRaisesRegex(ValueError, 'root text changed'):
            subject.verify_installed(self.root)

    def test_coherent_manifest_and_notice_rewrite_is_rejected(self):
        for row in self.report['license_texts']:
            path = self.root / row['path']
            path.write_bytes(path.read_bytes().replace(b'LLVM', b'Other'))
        path = self.root / subject.MANIFEST
        record = json.loads(path.read_text())
        for row in record['license_texts']:
            row['sha256'] = subject.sha((self.root / row['path']).read_bytes())
        path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            subject.verify_installed(self.root)

    def test_exact_binary_retention_overclaim_is_rejected(self):
        path = self.root / 'compliance/inventory.json'
        record = json.loads(path.read_text())
        next(row for row in record['components'] if row['id'] == subject.COMPONENT)['resolution'] = 'exact-linked-objects-proved'
        path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'qualified compiler-runtime attribution changed'):
            subject.verify_installed(self.root)

    def test_duplicate_and_missing_attribution_are_rejected(self):
        path = self.root / 'compliance/inventory.json'
        original = json.loads(path.read_text())
        row = next(row for row in original['components'] if row['id'] == subject.COMPONENT)
        for components in [original['components'] + [row], [r for r in original['components'] if r['id'] != subject.COMPONENT]]:
            with self.subTest(count=len(components)):
                path.write_text(json.dumps({**original, 'components': components}))
                with self.assertRaisesRegex(ValueError, 'qualified compiler-runtime attribution changed'):
                    subject.verify_installed(self.root)

    def test_generated_corpus_cannot_drop_credit_text(self):
        path = self.root / 'compliance/generated/THIRD_PARTY_NOTICES.md'
        path.write_text(path.read_text().replace('N: Howard Hinnant', 'credit omitted'))
        with self.assertRaisesRegex(ValueError, 'generated corpus omits complete'):
            subject.verify_installed(self.root)

    def test_publisher_build_binding_is_not_retargetable(self):
        path = self.root / 'compliance/evidence/viz-js-3.30.0/source-audit.json'
        record = json.loads(path.read_text())
        record['backend_publisher_dependencies'][0]['digest']['sha256'] = '0' * 64
        path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'publisher build binding changed'):
            subject.verify_installed(self.root)

    def test_raw_upstream_replay_rejects_changed_input(self):
        name = self.report['inputs'][0]['path'].replace('/', '--')
        (self.root / name).write_bytes(b'changed upstream file')
        with self.assertRaisesRegex(ValueError, 'immutable upstream input changed'):
            subject.verify_inputs(self.report, self.root)


if __name__ == '__main__':
    unittest.main()

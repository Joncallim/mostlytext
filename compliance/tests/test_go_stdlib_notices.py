"""Preserve exact supplemental comments and conservative source-build claims."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import prepare_go_stdlib_notices as prepare
import verify_go_stdlib_notices as verify


class GoStdlibNoticeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = Path(__file__).resolve().parents[2]
        for name in [verify.MANIFEST, verify.NOTICE, 'compliance/inventory.json', 'compliance/generated/THIRD_PARTY_NOTICES.md']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, target)
        self.report = json.loads((self.root / verify.MANIFEST).read_text())

    def test_exact_captured_source_notice_assembly_passes(self):
        result = verify.verify_installed(self.root)
        self.assertEqual(len(result['selected_files']), 1013)
        self.assertEqual(result['supplemental_source_files'], 21)
        self.assertEqual(len([g for g in result['fragments'] if g['kind'] == 'Go copyright']), 22)

    def test_notice_truncation_is_rejected(self):
        path = self.root / verify.NOTICE
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, 'notices changed'):
            verify.verify_installed(self.root)

    def test_coherent_manifest_notice_rewrite_is_rejected(self):
        for name in [verify.MANIFEST, verify.NOTICE]:
            path = self.root / name
            path.write_text(path.read_text().replace('Sun Microsystems', 'Uncredited author'))
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            verify.verify_installed(self.root)

    def test_claiming_exact_binary_retention_is_rejected(self):
        path = self.root / 'compliance/inventory.json'
        record = json.loads(path.read_text())
        row = next(row for row in record['components'] if row['id'] == 'd2-go-stdlib-source-notices')
        row['resolution'] = 'all-emitted-files-independently-proved'
        path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'qualified attribution'):
            verify.verify_installed(self.root)

    def test_duplicate_inventory_attribution_is_rejected(self):
        path = self.root / 'compliance/inventory.json'
        record = json.loads(path.read_text())
        record['components'].append(next(row for row in record['components'] if row['id'] == 'd2-go-stdlib-source-notices'))
        path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'qualified attribution'):
            verify.verify_installed(self.root)

    def test_generated_corpus_must_contain_the_complete_comments(self):
        path = self.root / 'compliance/generated/THIRD_PARTY_NOTICES.md'
        path.write_text(path.read_text().replace('provided that this notice', 'condition removed'))
        with self.assertRaisesRegex(ValueError, 'omit complete'):
            verify.verify_installed(self.root)

    def test_actual_sun_comments_require_the_preservation_condition(self):
        groups = [g for g in self.report['fragments'] if g['kind'] == 'Sun source notice']
        self.assertEqual(len(groups), 3)
        for group in groups:
            body = group['text'].encode()
            self.assertTrue(prepare.fragments('go/src/math/example.go', body))
            with self.assertRaises(ValueError):
                prepare.fragments('go/src/math/example.go', body.replace(b'provided that this notice', b'condition removed'))

    def test_actual_cephes_excerpt_keeps_the_free_use_and_disclaimer(self):
        group = next(g for g in self.report['fragments'] if g['kind'] == 'Cephes source notice')
        body = group['text'].encode()
        self.assertTrue(prepare.fragments('go/src/math/example.go', body))
        for token in [b'What you see here may be used freely', b'guarantee.', b'moshier@']:
            with self.subTest(token=token), self.assertRaises(ValueError):
                prepare.fragments('go/src/math/example.go', body.replace(token, b'removed'))

    def test_actual_fiat_notice_keeps_conditions_and_disclaimer(self):
        group = next(g for g in self.report['fragments'] if g['kind'] == 'fiat-crypto source notice')
        body = group['text'].encode() + b'// NewScalar returns a new scalar.\n'
        self.assertTrue(prepare.fragments('go/src/crypto/scalar.go', body))
        for token in [b'Redistributions of source code must retain', b'AS IS', b'POSSIBILITY OF SUCH DAMAGE']:
            with self.subTest(token=token), self.assertRaises(ValueError):
                prepare.fragments('go/src/crypto/scalar.go', body.replace(token, b'removed'))

    def test_changed_package_source_selection_is_rejected(self):
        path = self.root / 'graph.json'
        path.write_text(json.dumps({'Standard': True, 'ImportPath': 'math', 'Dir': '/fixture/go/src/math', 'GoFiles': ['changed.go']}))
        with self.assertRaisesRegex(ValueError, 'selection changed'):
            prepare.selection(path)


if __name__ == '__main__':
    unittest.main()

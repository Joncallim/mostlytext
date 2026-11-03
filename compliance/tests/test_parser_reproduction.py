"""Refuse incomplete or misidentified parser build receipts."""
import copy
import json
from pathlib import Path
import sys
import shutil
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_parser_reproduction as reproduction
import install_mermaid_notices as notices


class ParserReproductionTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.receipt = json.loads((self.root / reproduction.PACKET / 'reproduction.json').read_text())

    def test_current_complete_receipt_binds_the_shipped_parser(self):
        proof = reproduction.verify_installed(self.root)
        self.assertEqual(proof['vscodeUri']['archiveSHA256'], reproduction.VSCODE_ARCHIVE)

    def test_changed_rebuilt_bytes_do_not_qualify_as_reproduction(self):
        self.receipt['members'][0]['rebuiltSHA256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'member differs'):
            reproduction.validate_receipt(self.receipt)

    def test_incomplete_or_duplicate_member_sets_reject(self):
        for kind in ['missing', 'duplicate', 'unpaired']:
            value = copy.deepcopy(self.receipt)
            if kind == 'missing':
                value['members'].pop()
            elif kind == 'duplicate':
                value['members'][1]['member'] = value['members'][0]['member']
            else:
                value['members'][0]['member'] = 'dist/unrelated.mjs.map'
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                reproduction.validate_receipt(value)

    def test_wrong_source_or_compiler_identity_rejects(self):
        for key, value in [('sourceCommit', '0' * 40), ('esbuild', '0.27.7'), ('node', '26.11.1')]:
            receipt = dict(self.receipt, **{key: value})
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'identity/count'):
                reproduction.validate_receipt(receipt)

    def test_boolean_count_and_partial_success_are_not_complete_evidence(self):
        for value in [dict(self.receipt, identicalMembers=True), dict(self.receipt, different=['dist/changed.mjs'])]:
            with self.assertRaises(ValueError):
                reproduction.validate_receipt(value)

    def test_missing_pinned_proof_cannot_promote_inputs(self):
        with tempfile.TemporaryDirectory() as temp, self.assertRaisesRegex(ValueError, 'proof missing'):
            reproduction.verify_installed(Path(temp))

    def test_valid_receipt_does_not_authorize_a_different_current_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in [reproduction.PACKET, 'compliance/evidence/parser-publisher-provenance/manifest.json',
                         'compliance/evidence/mermaid-11.17.2/module-notice-map.json']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if (self.root / name).is_dir():
                    shutil.copytree(self.root / name, target)
                else:
                    shutil.copyfile(self.root / name, target)
            bundle = root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js'
            bundle.parent.mkdir(parents=True)
            bundle.write_bytes(b'changed current runtime')
            with self.assertRaisesRegex(ValueError, 'Current shipped Mermaid'):
                reproduction.verify_installed(root)

    def test_input_projection_requires_the_actual_archive_and_preserves_other_candidates(self):
        proof = reproduction.verify_installed(self.root)
        rows = notices.checked_map(self.root)['packages']
        row = next(item for item in rows if item['name'] == 'vscode-uri')
        projected = notices.reproduced_component(row, notices.projected_texts(row), proof)
        self.assertEqual(projected['npm'], 'vscode-uri@3.1.0')
        wrong = dict(row, tarball_sha256='0' * 64)
        with self.assertRaisesRegex(ValueError, 'input identity'):
            notices.reproduced_component(wrong, notices.projected_texts(row), proof)
        unresolved = next(item for item in rows if item['name'] == 'path-browserify')
        remaining = notices.reproduced_component(unresolved, notices.projected_texts(unresolved), proof)
        self.assertNotIn('npm', remaining)
        self.assertIn('unresolved', remaining['resolution'])


if __name__ == '__main__':
    unittest.main()

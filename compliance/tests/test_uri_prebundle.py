"""A full package reproduction cannot qualify partial, stale or substituted evidence."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_uri_prebundle as uri
import install_mermaid_notices as notices


class URIPrebundleTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.packet = self.root / uri.PACKET
        self.receipt = json.loads((self.packet / 'reproduction.json').read_text())

    def test_complete_current_proof_binds_the_shipped_nested_input(self):
        proof = uri.verify_installed(self.root)
        self.assertEqual(proof['scope'], 'complete-tagged-archive-reproduction; publisher-execution-unattested; independent-review-required')

    def test_archive_must_match_the_whole_published_archive(self):
        for change in [{'rebuiltArchiveSHA256': '0' * 64}, {'archiveByteIdentical': False},
                       {'publishedArchiveSHA256': '0' * 64}]:
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'archive'):
                uri.validate_receipt(dict(self.receipt, **change))

    def test_compiled_member_set_cannot_be_partial_duplicate_or_unrelated(self):
        for kind in ('missing', 'duplicate', 'renamed'):
            data = copy.deepcopy(self.receipt)
            rows = data['compiled']['members']
            if kind == 'missing':
                rows.pop()
            elif kind == 'duplicate':
                rows[1]['member'] = rows[0]['member']
            else:
                rows[0]['member'] = 'lib/esm/unrelated.mjs'
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, '13-member'):
                uri.validate_receipt(data)

    def test_changed_compiled_bytes_cannot_claim_equality(self):
        self.receipt['compiled']['members'][0]['rebuiltSHA256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'equality'):
            uri.validate_receipt(self.receipt)

    def test_boolean_counts_and_empty_member_bytes_do_not_qualify(self):
        for key in ('comparedMembers', 'identicalMembers'):
            data = copy.deepcopy(self.receipt)
            data['compiled'][key] = True
            with self.subTest(key=key), self.assertRaises(ValueError):
                uri.validate_receipt(data)
        self.receipt['compiled']['members'][0]['bytes'] = 0
        with self.assertRaisesRegex(ValueError, 'size'):
            uri.validate_receipt(self.receipt)

    def test_all_seventeen_package_members_must_be_present_and_equal(self):
        for kind in ('missing', 'duplicate', 'different'):
            data = copy.deepcopy(self.receipt)
            rows = data['payload']['members']
            if kind == 'missing':
                rows.pop()
            elif kind == 'duplicate':
                rows[1]['member'] = rows[0]['member']
            else:
                rows[0]['byteIdentical'] = False
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, '17-member'):
                uri.validate_receipt(data)

    def test_comparison_reference_is_not_the_frozen_compiler_resolution(self):
        self.receipt['toolchain']['webpack'] = '5.88.2'
        with self.assertRaisesRegex(ValueError, 'toolchain identity'):
            uri.validate_receipt(self.receipt)

    def test_wrong_source_or_source_mutation_is_not_the_restored_build(self):
        for change in [{'sourceCommit': '0' * 40}, {'sourceFilesVerified': 22},
                       {'changedSourceFiles': ['src/uri.ts']}]:
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'source/toolchain'):
                uri.validate_receipt(dict(self.receipt, **change))

    def test_nested_source_and_distributed_licenses_are_bound(self):
        for key in self.receipt['inputHashes']:
            data = copy.deepcopy(self.receipt)
            data['inputHashes'][key] = '0' * 64
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'linkage'):
                uri.validate_receipt(data)

    def test_actual_negative_control_cannot_be_replaced_with_a_success(self):
        positive = self.receipt['compiled']
        with self.assertRaisesRegex(ValueError, 'success/refusal'):
            uri.validate_comparison(positive, matching=False)
        negative = json.loads((self.packet / 'source-mutation-control.json').read_text())['comparison']
        with self.assertRaisesRegex(ValueError, 'success/refusal'):
            uri.validate_comparison(negative, matching=True)

    def test_missing_pinned_packet_refuses(self):
        with tempfile.TemporaryDirectory() as temp, self.assertRaisesRegex(ValueError, 'proof missing'):
            uri.verify_installed(Path(temp))

    def test_tampered_receipt_refuses_even_if_archive_field_still_says_match(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copytree(self.packet, root / uri.PACKET)
            path = root / uri.PACKET / 'reproduction.json'
            data = json.loads(path.read_text())
            data['toolchain']['webpack'] = '5.88.2'
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'Pinned URI reproduction file changed'):
                uri.verify_installed(root)

    def test_valid_old_receipt_does_not_authorize_a_changed_current_mermaid(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in [uri.PACKET, 'compliance/evidence/parser-runtime-reproduction',
                         'compliance/evidence/parser-publisher-provenance/manifest.json',
                         'compliance/evidence/mermaid-11.17.2/module-notice-map.json']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if (self.root / name).is_dir():
                    shutil.copytree(self.root / name, target)
                else:
                    shutil.copyfile(self.root / name, target)
            bundle = root / notices.SHIPPED
            bundle.parent.mkdir(parents=True)
            bundle.write_bytes(b'changed current runtime')
            with self.assertRaisesRegex(ValueError, 'Current shipped Mermaid differs'):
                uri.verify_installed(root)

    def test_reproduction_does_not_silently_promote_unattested_historical_identity(self):
        uri.verify_installed(self.root)
        rows = notices.checked_map(self.root)['packages']
        row = next(p for p in rows if p['name'] == 'path-browserify')
        outer = uri.checked_outer(self.root)
        projected = notices.reproduced_component(row, notices.projected_texts(row), outer)
        self.assertNotIn('npm', projected)
        self.assertIn('unresolved', projected['resolution'])


if __name__ == '__main__':
    unittest.main()

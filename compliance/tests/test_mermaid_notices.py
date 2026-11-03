"""Corruption and truthfulness controls for distributing captured package texts."""
import copy
import hashlib
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import install_mermaid_notices as notices


class MermaidNoticeTests(unittest.TestCase):
    def setUp(self):
        self.body = b'Complete original notice\n'
        self.spec = {'archive_path': 'LICENSE', 'bytes': len(self.body),
                     'sha256': hashlib.sha256(self.body).hexdigest()}
        self.row = {'name': 'vscode-uri', 'version': '3.1.0',
                    'package_license_expression': 'MIT', 'registry_url': 'https://registry.npmjs.org/vscode-uri/3.1.0',
                    'version_authority': 'content-matched candidate; original resolution not proved'}

    def test_committed_distribution_matches_all_reviewed_package_records(self):
        notices.verify_installed(TOOLS.parents[1])

    def test_preserves_every_notice_byte(self):
        self.assertEqual(notices.extract_text({'LICENSE': self.body}, self.spec), self.body)

    def test_changed_license_rejected(self):
        with self.assertRaisesRegex(ValueError, 'bytes changed'):
            notices.extract_text({'LICENSE': self.body.replace(b'original', b'altered!')}, self.spec)

    def test_changed_length_rejected_even_with_matching_digest(self):
        spec = dict(self.spec, bytes=1)
        with self.assertRaises(ValueError):
            notices.extract_text({'LICENSE': self.body}, spec)

    def test_readme_range_does_not_distribute_surrounding_prose(self):
        container = b'Introduction\n' + self.body + b'Other section\n'
        spec = dict(self.spec, archive_file_sha256=notices.sha(container), byte_start=13,
                    byte_end_exclusive=13 + len(self.body))
        self.assertEqual(notices.extract_text({'LICENSE': container}, spec), self.body)

    def test_readme_container_change_rejected(self):
        spec = dict(self.spec, archive_file_sha256='0' * 64, byte_start=0,
                    byte_end_exclusive=len(self.body))
        with self.assertRaisesRegex(ValueError, 'container digest'):
            notices.extract_text({'LICENSE': self.body}, spec)

    def test_out_of_bounds_range_rejected(self):
        spec = dict(self.spec, archive_file_sha256=notices.sha(self.body), byte_start=-1,
                    byte_end_exclusive=len(self.body))
        with self.assertRaisesRegex(ValueError, 'byte range'):
            notices.extract_text({'LICENSE': self.body}, spec)

    def test_candidates_never_get_exact_npm_identity(self):
        for name in notices.CANDIDATES:
            row = dict(self.row, name=name)
            component = notices.component(row, [self.spec])
            self.assertNotIn('npm', component)
            self.assertIn('unresolved', component['version'])
            self.assertIn('content-match-only', component['resolution'])
            self.assertIn('unresolved', component['name'])

    def test_exact_mapped_version_keeps_npm_identity(self):
        c = notices.component(dict(self.row, name='marked', version='16.3.0'), [self.spec])
        self.assertEqual(c['npm'], 'marked@16.3.0')
        self.assertEqual(c['version'], '16.3.0')

    def test_dompurify_records_only_captured_apache_option(self):
        c = notices.component(dict(self.row, name='dompurify', package_license_expression='(MPL-2.0 OR Apache-2.0)'), [self.spec])
        self.assertEqual(c['licence'], 'Apache-2.0')

    def test_candidate_promotion_missing_and_duplicate_records_rejected(self):
        expected = [notices.component(self.row, [self.spec])]
        cyto = {'id': 'cytoscape-via-mermaid', 'licence_texts': [{'sha256': 'eb319c6e6f233607f71e8e2f450391751883cfc0eeb3ca7ef574c13d1d9c2203'}]}
        baseline = {'components': expected + [cyto]}
        notices.verify_inventory(baseline, expected)
        for kind in ['promote', 'missing', 'duplicate', 'cytoscape']:
            with self.subTest(kind=kind):
                inv = copy.deepcopy(baseline)
                if kind == 'promote':
                    inv['components'][0]['npm'] = 'vscode-uri@3.1.0'
                    inv['components'][0]['resolution'] = 'exact'
                elif kind == 'missing':
                    inv['components'].pop(0)
                elif kind == 'duplicate':
                    inv['components'].append(inv['components'][0])
                else:
                    inv['components'].pop()
                with self.assertRaises(ValueError):
                    notices.verify_inventory(inv, expected)


if __name__ == '__main__':
    unittest.main()

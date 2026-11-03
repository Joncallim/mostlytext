"""Corruption and false-inclusion controls for the borrowed-code proof."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import audit_cytoscape_attribution as audit


class CytoscapeAttributionTests(unittest.TestCase):
    def setUp(self):
        self.source = '// credit\n\nfunction helper() {\n  use();\n}\nnext();\n'
        self.region = audit.fragment(self.source, 'function helper()', 'next();',
                                     '// credit', ['  use();'])

    def test_fragment_coordinates_are_code_lines_not_credit_lines(self):
        self.assertEqual(self.region['first_line'], 2)
        self.assertEqual(self.region['end_line_exclusive'], 5)
        self.assertEqual(self.region['probe_lines'], [3])
        self.assertEqual(self.region['source_sha256'],
                         hashlib.sha256(b'function helper() {\n  use();\n}\n').hexdigest())

    def test_each_probe_must_reach_generated_code(self):
        refs = audit.fragment_references([(0, 0, 1, 3, 2), (0, 10, 1, 3, 4)], 1, {'helper': self.region})
        self.assertEqual(refs['helper']['generated_references'], 2)
        self.assertEqual(refs['helper']['mapped_source_lines'], 1)
        self.assertEqual(refs['helper']['generated_probe_references'], [{'source_line': 4, 'references': 2}])

    def test_comment_mapping_cannot_prove_code_inclusion(self):
        with self.assertRaisesRegex(ValueError, 'mapped generated code'):
            audit.fragment_references([(0, 0, 1, 0, 2)], 1, {'helper': self.region})

    def test_other_fragment_code_cannot_substitute_for_borrowed_probe(self):
        with self.assertRaisesRegex(ValueError, 'specific borrowed-code probe'):
            audit.fragment_references([(0, 0, 1, 2, 2)], 1, {'helper': self.region})

    def test_identical_coordinates_in_another_source_do_not_count(self):
        with self.assertRaisesRegex(ValueError, 'mapped generated code'):
            audit.fragment_references([(0, 0, 0, 3, 2), (0, 4, None, 3, 2)], 1, {'helper': self.region})

    def test_all_distinct_probes_are_required(self):
        region = {**self.region, 'probe_lines': [3, 4]}
        with self.assertRaisesRegex(ValueError, 'specific borrowed-code probe'):
            audit.fragment_references([(0, 0, 1, 3, 2)], 1, {'helper': region})

    def test_missing_repeated_reordered_and_outside_boundaries_fail(self):
        cases = [self.source.replace('// credit', '// different'),
                 self.source + '// credit\n', self.source + 'function helper()\n',
                 self.source.replace('next();', '')]
        for source in cases:
            with self.subTest(source=source), self.assertRaises(ValueError):
                audit.fragment(source, 'function helper()', 'next();', '// credit', ['  use();'])
        with self.assertRaises(ValueError):
            audit.fragment(self.source, 'next();', 'function helper()', '// credit', ['  use();'])
        with self.assertRaises(ValueError):
            audit.fragment(self.source, 'function helper()', 'next();', '// credit', ['next();'])

    def test_no_probe_or_ambiguous_probe_is_not_a_proof(self):
        for probes in [[], ['// credit']]:
            with self.subTest(probes=probes), self.assertRaises(ValueError):
                audit.fragment(self.source, 'function helper()', 'next();', '// credit', probes)
        with self.assertRaises(ValueError):
            audit.fragment(self.source.replace('  use();', '  use();\n  use();'),
                           'function helper()', 'next();', '// credit', ['  use();'])

    def test_reference_byte_mutation_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'reference.txt'
            original = b'Copyright reference\nPermission text.\n'
            path.write_bytes(original)
            expected = hashlib.sha256(original).hexdigest()
            self.assertEqual(audit.checked_file(path, expected), original)
            path.write_bytes(original + b' ')
            with self.assertRaisesRegex(ValueError, 'digest changed'):
                audit.checked_file(path, expected)

    def test_committed_texts_match_the_captured_upstream_licenses(self):
        expected = {
            'cytoscape--MIT.txt': 'eb319c6e6f233607f71e8e2f450391751883cfc0eeb3ca7ef574c13d1d9c2203',
            'cytoscape-bezier--MIT.txt': '32bfd1097d45b41ca6792bf07b389b26ee4045e7f7db28349f4199eef889c516',
            'cytoscape-jquery-events--MIT.txt': '44254c9a91a4647b9192584f17b2d27bf43696ba1ea16b0e88ac7bd6bf0780f1',
        }
        for name, digest in expected.items():
            with self.subTest(name=name):
                body = (audit.ROOT / 'compliance/licenses' / name).read_bytes()
                self.assertEqual(hashlib.sha256(body).hexdigest(), digest)
                self.assertIn(b'Permission is hereby granted', body)

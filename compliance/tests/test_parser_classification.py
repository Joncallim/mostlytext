"""Prevent syntax-only receipts from losing original positions or claiming clearance."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_parser_classification as classifier


class ParserClassificationTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.data = json.loads((self.root / classifier.PACKET / 'classification.json').read_text())
        self.original = json.loads((self.root / classifier.INDEX).read_text())

    def test_complete_current_receipt_is_bound_to_reproduction_and_runtime(self):
        classifier.verify_installed(self.root)

    def test_missing_duplicate_and_reordered_rows_fail(self):
        for kind in ['missing', 'duplicate', 'reordered']:
            value = copy.deepcopy(self.data)
            if kind == 'missing': value['positions'].pop()
            elif kind == 'duplicate': value['positions'][1] = value['positions'][0]
            else: value['positions'][0:2] = reversed(value['positions'][0:2])
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                classifier.validate_receipt(value, self.original)

    def test_changed_original_coordinates_and_member_hash_fail(self):
        for key, new in [('parser_utf16_column', 987), ('parser_member_sha256', '0' * 64),
                         ('outer_generated_positions', [[1, 1]]), ('outer_reference_count', 0)]:
            original = copy.deepcopy(self.original)
            row = self.data['positions'][0]['original_row_index']
            original['positions'][row][key] = new
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'binding changed'):
                classifier.validate_receipt(self.data, original)

    def test_wrong_tool_or_false_rights_clearance_fails(self):
        for key, new in [('parser', 'acorn@8.0.0'), ('parser_module_sha256', '0' * 64),
                         ('independent_review_required', False), ('scope', 'All rights cleared'),
                         ('parser_controls', True)]:
            data = dict(self.data, **{key:new})
            with self.subTest(key=key), self.assertRaises(ValueError):
                classifier.validate_receipt(data, self.original)
        with self.assertRaises(ValueError):
            classifier.validate_receipt(dict(self.data, rights_cleared=True), self.original)

    def test_unknown_category_and_relabelled_position_fail(self):
        for category in ['cleared', 'unclassified']:
            data = copy.deepcopy(self.data)
            data['positions'][0]['technical_category'] = category
            with self.subTest(category=category), self.assertRaises(ValueError):
                classifier.validate_receipt(data, self.original)

    def test_partial_or_boolean_totals_fail(self):
        for data in [dict(self.data, total_references=True), dict(self.data, total_references=3428),
                     dict(self.data, categories=dict(classifier.EXPECTED, unclassified=0))]:
            with self.assertRaises(ValueError): classifier.validate_receipt(data, self.original)

    def test_missing_pinned_proof_fails(self):
        with tempfile.TemporaryDirectory() as folder, self.assertRaisesRegex(ValueError, 'proof missing'):
            classifier.verify_installed(Path(folder))


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Pure geometry/admission controls using the exact downloaded first selection record."""
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('placed_canary', Path(__file__).with_name('verify-placed-pdf-canary.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
FIXTURE = Path('.github/fixtures/original-canary-selections.json.gz')


class PlacementControls(unittest.TestCase):
    def setUp(self):
        raw = gzip.decompress(FIXTURE.read_bytes())
        self.assertEqual(hashlib.sha256(raw).hexdigest(), 'beb1f04a66d47fb3a79a4699d67fb488c98d6509035fdbe9835a1ec947b641e0')
        self.original = json.loads(raw)
        self.page = copy.deepcopy(self.original['pages'][0])

    def reject(self):
        with self.assertRaises(ValueError):
            probe.placed_heading(self.page)

    def test_actual_original_heading_is_placed_but_two_pages_refuse(self):
        result = probe.evaluate(self.original)
        self.assertEqual(result['ordered_heading'], 'NATIVE_EXPORT_CANARY')
        self.assertEqual(result['page_count'], 2)
        self.assertFalse(result['short_fixture_accepted'])
        self.assertFalse(self.original['original_guard_predicates']['exact_raw_canary'])

    def test_single_page_policy_is_separate_from_placement(self):
        self.assertTrue(probe.evaluate({'pages': [self.page]})['short_fixture_accepted'])

    def test_wrong_actual_visual_order_refuses_even_with_original_raw_text(self):
        rows = self.page['character_geometry']
        rows[0]['selection_bounds'], rows[1]['selection_bounds'] = rows[1]['selection_bounds'], rows[0]['selection_bounds']
        self.reject()

    def test_missing_underscore_refuses(self):
        self.page['character_geometry'][21]['selection_bounds'][3] /= 2
        self.reject()

    def test_duplicate_index_refuses(self):
        self.page['character_geometry'][21]['utf16_index'] = 0
        self.reject()

    def test_missing_record_refuses(self):
        self.page['character_geometry'].pop()
        self.reject()

    def test_wrong_selection_and_missing_selection_refuse(self):
        for key, value in [('selection_text', 'X'), ('selection_present', False), ('selection_geometry_state', 'missing')]:
            with self.subTest(key=key):
                self.setUp()
                self.page['character_geometry'][0][key] = value
                self.reject()

    def test_off_row_off_page_collapsed_and_separated_positions_refuse(self):
        for component, value in [(1, 610), (0, -1), (0, 126.16537634720001), (0, 10)]:
            with self.subTest(component=component, value=value):
                self.setUp()
                self.page['character_geometry'][0]['selection_bounds'][component] = value
                self.reject()

    def test_nonfinite_zero_and_boolean_rectangles_refuse(self):
        for value in [float('nan'), float('inf'), 0, -1, True]:
            with self.subTest(value=value):
                self.setUp()
                self.page['character_geometry'][0]['selection_bounds'][3] = value
                self.reject()

    def test_changed_raw_character_and_extra_largest_glyph_refuse(self):
        self.page['character_geometry'][0]['raw_index_text'] = 'X'
        self.reject()
        self.setUp()
        self.page['character_geometry'][25]['selection_bounds'][3] = self.page['character_geometry'][0]['selection_bounds'][3]
        self.reject()

    def test_both_immutable_actual_pdf_records_are_admitted(self):
        actual = probe.inputs()
        self.assertEqual({n: (probe.sha(b), len(b)) for n, b in actual.items()}, probe.PDFS)


class RecordAdmission(unittest.TestCase):
    def exercise(self, *, name='record.gz', declared=11, digest=None, symlink=False, raw=b'owned bytes'):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            actual = root / 'record.gz'
            actual.write_bytes(gzip.compress(raw, mtime=0))
            if symlink:
                (root / 'redirect.gz').symlink_to(actual)
                name = 'redirect.gz'
            return probe.decoded_record(root, {'file': name, 'bytes': declared, 'sha256': digest or hashlib.sha256(raw).hexdigest()})

    def test_exact_record_passes(self):
        self.assertEqual(self.exercise(), b'owned bytes')

    def test_redirect_and_symlink_refuse(self):
        for options in [{'name': '../record.gz'}, {'name': '/tmp/record.gz'}, {'symlink': True}]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.exercise(**options)

    def test_byte_change_truncation_and_compressed_bomb_refuse(self):
        for options in [{'digest': '0' * 64}, {'declared': 1}, {'declared': True}, {'raw': b'0' * 1_000_000}]:
            with self.subTest(options=options.keys()), self.assertRaises(ValueError):
                self.exercise(**options)


if __name__ == '__main__':
    unittest.main()

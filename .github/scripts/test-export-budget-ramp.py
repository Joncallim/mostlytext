#!/usr/bin/env python3
"""Source-only checks for export ramp fixtures, stop guards and integrity receipts."""
import hashlib
import json
from pathlib import Path
import runpy
import tempfile
import unittest


SCRIPTS = Path(__file__).parent
generator = runpy.run_path(str(SCRIPTS / 'prepare-export-budget-ramp.py'))
runner = runpy.run_path(str(SCRIPTS / 'run-export-budget-ramp.py'))


class RampControlsTests(unittest.TestCase):
    def test_fixed_ladder_and_policy_refusal_kinds(self):
        self.assertEqual(len(generator['CASE_ORDER']), 20)
        self.assertEqual(len(set(generator['CASE_ORDER'])), 20)
        self.assertEqual(generator['case_definition']('source32')['source_bytes'], 32 << 20)
        self.assertEqual(generator['case_definition']('single32')['assets'], {'pixel.png': 'a32'})
        self.assertEqual(generator['case_definition']('repeat5')['occurrences'], 5)
        self.assertEqual(generator['case_definition']('repeat3')['refusal_kind'], 'budget-exceeded')
        self.assertEqual(generator['case_definition']('aggregate96')['refusal_kind'], 'budget-exceeded')
        self.assertEqual(generator['case_definition']('aggregate64')['refusal'], False)
        near = generator['case_definition']('repeatNearFinal')
        self.assertEqual(near['assets'], {'pixel.png': 'a32', 'near.png': 'near32'})
        self.assertEqual(near['occurrences'], 3)
        self.assertEqual(near['estimated_data_uri_bytes'], 134206874)
        self.assertEqual(near['estimated_shell_headroom_bytes'], 10854)
        self.assertEqual(generator['ASSET_SIZES']['near32'], (32 << 20) - (8 << 10))
        self.assertEqual(generator['references_for_case']('repeatNearFinal', near),
                         ['pixel.png'] * 2 + ['near.png'])
        self.assertEqual(generator['case_definition']('repeat6refusal')['refusal_kind'], 'budget-exceeded')
        self.assertEqual(generator['case_definition']('occ65537refusal')['refusal_kind'], 'budget-exceeded')
        self.assertEqual(generator['case_definition']('aggregateOverRefusal')['refusal_kind'],
                         'unresolved-resources')
        self.assertEqual(generator['case_definition']('aggregate128')['assets'],
                         {f'{letter}.png': f'{letter}32' for letter in 'abcd'})
        self.assertEqual(len(generator['case_definition']('distinct512')['assets']), 512)
        self.assertEqual(generator['case_definition']('distinct513refusal')['refusal_kind'],
                         'unresolved-resources')

    def test_valid_png_crc_and_corruption_detection(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'pixel.png'
            generator['make_png'](path, 4096, 1)
            generator['assert_png'](path)
            self.assertEqual(path.stat().st_size, 4096)
            data = bytearray(path.read_bytes())
            data[60] ^= 1
            path.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'CRC'):
                generator['assert_png'](path)
            generator['make_distinct_png'](path, 512)
            generator['assert_png'](path)
            self.assertEqual(path.stat().st_size, len(generator['SMALL_PNG']) + 24)

    def test_source_target_is_exact_and_compact_when_rendered(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'source.md'
            generator['write_source'](path, 8192)
            self.assertEqual(path.stat().st_size, 8192)
            self.assertTrue(path.read_bytes().startswith(b'# Budget ramp\n\n'))
            self.assertEqual(path.read_bytes()[len(b'# Budget ramp\n\n'):],
                             b' ' * (8192 - len(b'# Budget ramp\n\n')))

    def test_growth_and_time_guards(self):
        observation = {'app_rss_bytes': 100 << 20, 'new_webkit_rss_bytes': 0}
        self.assertIsNone(runner['guard_reason'](10, 10, observation))
        self.assertEqual(runner['guard_reason'](180, 10, observation), 'case-time-ceiling')
        self.assertEqual(runner['guard_reason'](10, 1800, observation), 'total-time-ceiling')
        observation['app_rss_bytes'] = 1536 << 20
        self.assertEqual(runner['guard_reason'](10, 10, observation), 'cohort-rss-ceiling')

    def test_output_digest_match_and_refusal_integrity(self):
        with tempfile.TemporaryDirectory() as temporary:
            case = Path(temporary)
            (case / 'measurements').mkdir()
            content = b'<!doctype html>published'
            digest = hashlib.sha256(content).hexdigest()
            (case / 'export.html').write_bytes(content)
            expected = {'name': 'source8', 'source_bytes': 100, 'resource_bytes': 0,
                        'occurrences': 0, 'refusal': False, 'refusal_kind': None}
            row = {'case': 'source8', 'outcome': 'published', 'source_bytes': 100,
                   'resource_bytes': 0, 'occurrences': 0, 'app_peak_before_bytes': 1,
                   'app_peak_after_bytes': 2, 'output_bytes': len(content), 'output_sha256': digest}
            record = case / 'measurements' / 'result.json'
            record.write_text(json.dumps(row))
            self.assertEqual(runner['inspect_output'](case, expected)['output_sha256'], digest)
            self.assertFalse((case / 'export.html').exists())
            (case / 'export.html').write_bytes(content)
            row['output_sha256'] = '0' * 64
            record.write_text(json.dumps(row))
            with self.assertRaisesRegex(RuntimeError, 'digest'):
                runner['inspect_output'](case, expected)
            self.assertTrue((case / 'export.html').exists())
            (case / 'export.html').unlink()
            refusal = {**expected, 'name': 'aggregateOverRefusal', 'occurrences': 5,
                       'refusal': True, 'refusal_kind': 'unresolved-resources'}
            row.update({'case': refusal['name'], 'outcome': 'budget-refusal',
                        'occurrences': 5, 'refusal_kind': 'unresolved-resources', 'output_exists': False})
            record.write_text(json.dumps(row))
            self.assertEqual(runner['inspect_output'](case, refusal)['output_exists'], False)
            (case / 'export.html').write_bytes(b'partial')
            with self.assertRaisesRegex(RuntimeError, 'published output'):
                runner['inspect_output'](case, refusal)


if __name__ == '__main__':
    unittest.main()

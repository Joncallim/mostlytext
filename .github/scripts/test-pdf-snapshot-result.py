#!/usr/bin/env python3
"""Actual qualified rendering evidence admission and hostile mutation controls; no native execution."""
import copy
import gzip
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('frames', Path(__file__).with_name('read-pdf-snapshot-frames.py'))
frames = importlib.util.module_from_spec(spec); spec.loader.exec_module(frames)
PACKET = Path(__file__).resolve().parents[2] / 'planning/downstream/evidence/pdf-scrollbar-prototype-qualified-2026-11-08'


class NativeCanvasEvidence(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        manifest = json.loads((PACKET / 'manifest.json').read_bytes())
        for row in manifest['records']:
            name = row['original_name']
            if not (name.endswith('.png') or name == 'snapshot-frame-observations.json'):
                continue
            raw = gzip.decompress((PACKET / row['file']).read_bytes())
            self.assertEqual(len(raw), row['bytes'])
            self.assertEqual(__import__('hashlib').sha256(raw).hexdigest(), row['sha256'])
            (self.root / name).write_bytes(raw)
        self.observed = json.loads((self.root / 'snapshot-frame-observations.json').read_bytes())

    def candidate(self):
        return self.observed['completed_cases'][-1]

    def test_actual_qualified_short_and_authored_space_pages_pass(self):
        frames.verify_candidate_rendering(self.root, self.observed)

    def test_the_actual_observed_narrowed_boundary_cannot_qualify(self):
        self.candidate()['snapshot_media_box'] = self.observed['completed_cases'][4]['snapshot_media_box']
        with self.assertRaises(RuntimeError): frames.verify_candidate_rendering(self.root, self.observed)

    def test_trimmed_authored_space_or_extra_short_page_refuses(self):
        for index, replacement in [(-1, self.candidate()['pages'][:1]), (5, self.observed['completed_cases'][0]['pages'])]:
            observed = copy.deepcopy(self.observed); observed['completed_cases'][index]['pages'] = replacement
            with self.assertRaises(RuntimeError): frames.verify_candidate_rendering(self.root, observed)

    def test_changed_text_pixels_or_missing_control_refuses(self):
        for mutation in ['text', 'pixels', 'missing']:
            observed = copy.deepcopy(self.observed)
            if mutation == 'text': observed['completed_cases'][-1]['pages'][0]['raw_text'] += 'changed'
            elif mutation == 'pixels': observed['completed_cases'][-1]['pages'][0]['actual_raster_nonwhite_pixels'] += 1
            else: observed['completed_cases'].pop(0)
            with self.assertRaises(RuntimeError): frames.verify_candidate_rendering(self.root, observed)

    def test_changed_or_redirected_candidate_png_refuses(self):
        path = self.root / 'css-paper-page-1.png'
        original = path.read_bytes()
        path.write_bytes(original + b'changed')
        with self.assertRaises(RuntimeError): frames.verify_candidate_rendering(self.root, self.observed)
        path.unlink(); path.symlink_to(self.root / 'original-page-1.png')
        with self.assertRaises(RuntimeError): frames.verify_candidate_rendering(self.root, self.observed)


if __name__ == '__main__':
    unittest.main()

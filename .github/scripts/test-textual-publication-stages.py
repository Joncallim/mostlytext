#!/usr/bin/env python3
"""Pure exact-source admission/transform controls; no fork, GUI or native execution."""
import gzip
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('stage_patcher', Path(__file__).with_name('patch-textual-publication-stages.py'))
patcher = importlib.util.module_from_spec(spec); spec.loader.exec_module(patcher)
PACKET = Path(__file__).resolve().parents[2] / 'planning/downstream/evidence/textual-publication-stage-originals-2026-11-08'


def originals():
    manifest = json.loads((PACKET / 'manifest.json').read_bytes())
    assert manifest['original_pin'] == patcher.PIN
    result = {}
    for row in manifest['records']:
        raw = gzip.decompress((PACKET / row['file']).read_bytes())
        assert len(raw) == row['bytes'] and patcher.sha(raw) == row['sha256']
        result[row['original_path']] = raw
    return result


class ExactRendererAdmission(unittest.TestCase):
    def test_exact_originals_transform_without_new_view_observers(self):
        before = originals(); after = patcher.transformed(before)
        self.assertNotIn(b'print(', patcher.HELPER)
        self.assertIn(b'events.count < 4000', patcher.HELPER)
        self.assertIn(b'overflow = true', patcher.HELPER)
        self.assertIn(b'public static func snapshot()', patcher.HELPER)
        self.assertEqual(set(after), set(before) | {patcher.HELPER_PATH})
        for name, raw in before.items():
            for token in [b'.task(', b'.onChange(', b'.onGeometryChange(', b'.customAttribute(']:
                self.assertEqual(after[name].count(token), raw.count(token))

    def test_current_input_prototype_removes_both_deferred_publications(self):
        before = originals(); candidate = patcher.transformed(before, 'current-input')
        inline = candidate['Sources/Textual/Internal/InlineText/WithInlineStyle.swift']
        fragment = candidate['Sources/Textual/Internal/TextFragment/TextFragment.swift']
        self.assertNotIn(b'@State private var output', inline)
        self.assertNotIn(b'.onChange(', inline)
        self.assertIn(b'content(output)', inline)
        self.assertIn(b') -> AttributedString {', inline)
        self.assertNotIn(b'.onChange(', fragment)
        self.assertIn(b'self.content == content, self.environment == environment', fragment)
        self.assertIn(b'guard builder === expected else { return }', fragment)
        self.assertEqual(fragment.count(b'.onGeometryChange('), before['Sources/Textual/Internal/TextFragment/TextFragment.swift'].count(b'.onGeometryChange('))

    def test_unknown_variant_refuses_before_transform(self):
        with self.assertRaises(RuntimeError): patcher.transformed(originals(), 'unreviewed')


    def test_wrong_original_byte_or_already_patched_source_refuses(self):
        before = originals(); name = next(iter(before))
        for replacement in [before[name] + b'\n', patcher.transformed(before)[name]]:
            changed = dict(before); changed[name] = replacement
            with self.assertRaises(RuntimeError): patcher.transformed(changed)

    def test_missing_or_unknown_original_file_refuses(self):
        before = originals(); missing = dict(before); missing.pop(next(iter(before)))
        for changed in [missing, dict(before, unknown=b'not a pinned file')]:
            with self.assertRaises(RuntimeError): patcher.transformed(changed)

    def test_missing_or_duplicate_existing_statement_refuses(self):
        for raw in [b'absent', b'statement statement']:
            with self.assertRaises(RuntimeError): patcher.replace_once(raw, 'statement', 'log and statement')


if __name__ == '__main__':
    unittest.main()

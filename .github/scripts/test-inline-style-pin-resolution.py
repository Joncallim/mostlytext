#!/usr/bin/env python3
"""Pure graph-admission controls; never run SwiftPM or a native product."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('pin_resolver', Path(__file__).with_name('resolve-inline-style-pin.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class LockControls(unittest.TestCase):
    def setUp(self):
        self.old = json.loads(Path('MacDown2/Packages/MacDownKit/Package.resolved').read_bytes())
        self.new = copy.deepcopy(self.old)
        next(p for p in self.new['pins'] if p['identity'] == 'textual')['state']['revision'] = probe.NEW

    def test_exact_single_immutable_change_accepts_with_real_resolver_metadata(self):
        self.new['originHash'] = 'different resolver metadata'
        probe.validate_pins(self.old, self.new)

    def test_unchanged_or_wrong_target_revision_refuses(self):
        for revision in [probe.OLD, '0' * 40]:
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                new = copy.deepcopy(self.new)
                next(p for p in new['pins'] if p['identity'] == 'textual')['state']['revision'] = revision
                probe.validate_pins(self.old, new)

    def test_other_dependency_revision_or_location_change_refuses(self):
        other = next(p for p in self.new['pins'] if p['identity'] != 'textual')
        for key, value in [('location', 'https://example.invalid/other'), ('state', {'revision': '0' * 40})]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                new = copy.deepcopy(self.new)
                next(p for p in new['pins'] if p['identity'] == other['identity'])[key] = value
                probe.validate_pins(self.old, new)

    def test_missing_extra_and_duplicate_packages_refuse(self):
        for rows in [self.new['pins'][:-1], self.new['pins'] + [self.new['pins'][0]], self.new['pins'][:-1] + [self.new['pins'][0]]]:
            with self.subTest(count=len(rows)), self.assertRaises(ValueError):
                probe.validate_pins(self.old, {**self.new, 'pins': rows})


if __name__ == '__main__':
    unittest.main()

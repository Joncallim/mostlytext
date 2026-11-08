#!/usr/bin/env python3
"""Pure process-selection checks; these tests never launch an application."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('export_memory', Path(__file__).with_name('sample-export-budget-memory.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProcessSelectionTests(unittest.TestCase):
    def test_only_exact_app_and_new_same_owner_webkit_helpers_are_counted(self):
        raw = '\n'.join([
            '101 501 100 /owned/MacDown2',
            '102 501 200 /owned/MacDown2-helper',
            '103 501 300 /System/com.apple.WebKit.WebContent',
            '104 501 400 /System/com.apple.WebKit.GPU',
            '105 501 500 /System/com.apple.WebKit.Networking',
            '106 501 600 /System/com.apple.WebKit.WebContent',
            '107 502 700 /owned/MacDown2',
            'bad row',
        ])
        rows = probe.parse_ps(raw, 501)
        sample = probe.sample(rows, Path('/owned/MacDown2'), {106})
        self.assertEqual(sample['app_rss_bytes'], 100 * 1024)
        self.assertEqual(sample['new_webkit_rss_bytes'], (300 + 400 + 500) * 1024)
        self.assertEqual(sample['new_webkit_processes'], 3)

    def test_absent_app_or_helpers_stays_explicitly_zero(self):
        rows = probe.parse_ps('111 501 200 /other/App\n112 502 300 /System/com.apple.WebKit.WebContent', 501)
        self.assertEqual(probe.sample(rows, Path('/owned/MacDown2'), set()),
                         {'app_rss_bytes': 0, 'new_webkit_rss_bytes': 0, 'new_webkit_processes': 0})


if __name__ == '__main__':
    unittest.main()

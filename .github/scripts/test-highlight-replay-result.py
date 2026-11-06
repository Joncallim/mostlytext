#!/usr/bin/env python3
"""Pure checks that incomplete or crashed native replays cannot qualify."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('highlight_read', Path(__file__).with_name('run-highlight-read-diagnostics.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

GOOD = ('HIGHLIGHT_READ_CONTROL events=["background-held", "released"] sourceBytes=73956\n'
        'Test run with 2 tests in 2 suites passed\n')
EXIT = 'Process 1456 exited with status = 0 (0x00000000)\n'


class ReplayQualificationTests(unittest.TestCase):
    def test_direct_and_debugger_require_their_actual_success_signals(self):
        self.assertTrue(module.replay_passed(0, GOOD))
        self.assertTrue(module.replay_passed(0, GOOD + EXIT, under_debugger=True))
        self.assertFalse(module.replay_passed(0, GOOD, under_debugger=True))
        self.assertFalse(module.replay_passed(1, GOOD))
        self.assertFalse(module.replay_passed(0, GOOD + EXIT.replace('= 0 ', '= 1 '), under_debugger=True))

    def test_real_background_entry_allows_an_earlier_main_lookup(self):
        self.assertTrue(module.replay_passed(0, GOOD.replace('["background-held"', '["main-lookup", "background-held"')))

    def test_missing_partial_duplicate_or_timed_out_controls_are_rejected(self):
        for bad in [GOOD.replace('2 tests in 2 suites', '1 test in 1 suite'),
                    GOOD.replace('background-held', 'main-lookup'),
                    GOOD.replace('"released"', '"hold-timed-out", "released"'),
                    GOOD.replace('"released"', '"background-held", "released"'),
                    GOOD.replace('"released"', 'broken-json'),
                    GOOD + 'recorded an issue at fixture.swift:10']:
            with self.subTest(log=bad):
                self.assertFalse(module.replay_passed(0, bad))

    def test_a_success_summary_cannot_hide_a_crash_or_restart(self):
        for failure in ['Program crashed:', 'stop reason = signal', 'Fatal error:',
                        'Restarting after unexpected']:
            with self.subTest(failure=failure):
                self.assertFalse(module.replay_passed(0, GOOD + EXIT + failure, under_debugger=True))


if __name__ == '__main__':
    unittest.main()

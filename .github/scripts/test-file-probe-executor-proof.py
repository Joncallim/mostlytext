#!/usr/bin/env python3
"""Exercise real Swift Testing issue output and reject unrelated counterexample failures."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('file_probe_executor', HERE / 'run-file-probe-executor-proof.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
SOURCE = (HERE.parent.parent / 'MacDown2/Packages/MacDownKit/Tests/FileCoreTests/DocumentFileProbeExecutionTests.swift').read_text()
DETAIL = '↳ External snapshot read and digest must run away from the main thread'


class CounterexampleOutputTests(unittest.TestCase):
    def logs(self, phase='main-actor-mutant'):
        for configuration in ['debug', 'release']:
            yield (HERE / 'file-probe-executor-fixtures' / (configuration + '-' + phase + '.log')).read_text()

    def reject_changed(self, before, after):
        for log in self.logs():
            self.assertIn(before, log)
            with self.assertRaises(RuntimeError):
                MODULE.verify_counterexample_issues(log.replace(before, after, 1), SOURCE)

    def test_actual_both_configurations_attach_details_on_next_line(self):
        for log in self.logs():
            MODULE.verify_counterexample_issues(log, SOURCE)

    def test_actual_passing_output_cannot_count_as_counterexample(self):
        for log in self.logs('original'):
            with self.assertRaises(RuntimeError):
                MODULE.verify_counterexample_issues(log, SOURCE)

    def test_missing_detail(self):
        self.reject_changed(DETAIL, '')

    def test_detached_detail(self):
        self.reject_changed(DETAIL, 'An intervening issue\n' + DETAIL)

    def test_wrong_detail(self):
        self.reject_changed(DETAIL, '↳ Snapshot bytes changed')

    def test_wrong_source(self):
        self.reject_changed('DocumentFileProbeExecutionTests.swift:41:9:', 'AnotherTest.swift:41:9:')

    def test_wrong_assertion_location(self):
        self.reject_changed('.swift:41:9:', '.swift:42:9:')

    def test_wrong_method(self):
        self.reject_changed('✘ Test movedSnapshotReadsAndHashesAwayFromTheMainThread(', '✘ Test anotherMethod(')

    def test_wrong_expression(self):
        self.reject_changed('Expectation failed: !((samples → [true]).contains(true) → true)', 'Expectation failed: snapshot.text == wrong')

    def test_duplicate_size(self):
        self.reject_changed('recorded an issue with 1 argument utf8Bytes → 10000000 ', 'recorded an issue with 1 argument utf8Bytes → 1000000 ')

    def test_unexpected_size(self):
        self.reject_changed('recorded an issue with 1 argument utf8Bytes → 1000000 ', 'recorded an issue with 1 argument utf8Bytes → 1 ')

    def test_additional_issue(self):
        for log in self.logs():
            with self.assertRaises(RuntimeError):
                MODULE.verify_counterexample_issues(log + '\n✘ Test anotherTest recorded an issue: unrelated failure\n', SOURCE)

    def test_truncated_detail_at_end(self):
        for log in self.logs():
            index = log.rindex('✘ Test movedSnapshotReadsAndHashesAwayFromTheMainThread(utf8Bytes:) recorded an issue')
            truncated = log[:index] + log[index:].splitlines()[0]
            with self.assertRaises(RuntimeError):
                MODULE.verify_counterexample_issues(truncated, SOURCE)

    def test_changed_assertion_source(self):
        for log in self.logs():
            with self.assertRaises(RuntimeError):
                MODULE.verify_counterexample_issues(log, SOURCE.replace('!samples.contains(true)', 'true'))


if __name__ == '__main__':
    unittest.main()

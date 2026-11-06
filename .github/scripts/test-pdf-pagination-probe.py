#!/usr/bin/env python3
"""Fail-closed result controls for genuine hosted PDF execution receipts."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('pdf_probe', Path(__file__).with_name('verify-pdf-pagination-probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class PDFResultTests(unittest.TestCase):
    def setUp(self):
        self.log = '\n'.join('Test ' + n + '() passed after 0.1 seconds.' for n in sorted(probe.TESTS))
        self.log += '\nSuite PDFExportAdapterTests passed.\nTest run with 9 tests in 1 suite passed.'
        self.identity = {'app': '/tmp/build/Release/MacDown2.app/Contents/MacOS/MacDown2', 'app_sha256': 'a' * 64,
                         'command': ['xcodebuild', '-configuration', 'Release', 'ENABLE_TESTABILITY=YES',
                                     'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) RELEASE_PREVIEW_PROBE PDF_PAGINATION_PROBE',
                                     '-only-testing:MacDown2Tests/PDFExportAdapterTests', 'test-without-building']}
        self.status = {'returncode': 0, 'timed_out': False, 'cancelled': False,
                       'elapsed_seconds': 5, 'app_cleanup_requested': []}

    def test_complete_original_selection_accepts(self):
        probe.validate_execution(self.log, self.identity, self.status)

    def test_missing_or_skipped_print_positive_refuses(self):
        for name in ['exportingALongDocumentProducesARealMultiPagePDF', 'exportedPDFReplacesAnyExistingFileAtomically']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                probe.validate_execution(self.log.replace('Test ' + name + '() passed', 'Test ' + name + '() skipped'),
                                         self.identity, self.status)

    def test_false_green_summary_or_recorded_issue_refuses(self):
        for log in [self.log.split('\n', 1)[1], self.log.replace('9 tests', '8 tests'),
                    self.log + '\nTest print() recorded an issue', self.log + '\nProgram crashed:']:
            with self.subTest(log=log[-100:]), self.assertRaises(ValueError):
                probe.validate_execution(log, self.identity, self.status)

    def test_missing_failed_timed_out_cancelled_or_cleanup_status_refuses(self):
        for changes in [{}, {'returncode': 65}, {'timed_out': True}, {'cancelled': True},
                        {'elapsed_seconds': 600}, {'app_cleanup_requested': [{'pid': 123}]}]:
            status = copy.deepcopy(self.status)
            if changes:
                status.update(changes)
            else:
                del status['timed_out']
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                probe.validate_execution(self.log, self.identity, status)

    def test_wrong_configuration_condition_selection_or_app_refuses(self):
        for original, replacement in [('Release', 'Debug'), ('RELEASE_PREVIEW_PROBE', 'OTHER_SUPPORT'), ('PDF_PAGINATION_PROBE', 'SOME_OTHER_CONDITION'),
                                      ('-only-testing:MacDown2Tests/PDFExportAdapterTests',
                                       '-only-testing:MacDown2Tests/PDFExportAdapterTests/hardenedHTMLRetainsThePDFPolicy')]:
            identity = copy.deepcopy(self.identity)
            identity['command'] = [c.replace(original, replacement) for c in identity['command']]
            with self.subTest(original=original), self.assertRaises(ValueError):
                probe.validate_execution(self.log, identity, self.status)
        for key, value in [('app', '/tmp/standalone-pdf-probe'), ('app_sha256', '')]:
            identity = dict(self.identity, **{key: value})
            with self.subTest(key=key), self.assertRaises(ValueError):
                probe.validate_execution(self.log, identity, self.status)


if __name__ == '__main__':
    unittest.main()

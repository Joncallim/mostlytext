#!/usr/bin/env python3
"""Fail-closed result controls for genuine hosted PDF execution receipts."""
import copy
import importlib.util
import json
import os
import platform
import pwd
import subprocess
import sys
import tempfile
from unittest import mock
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


class PDFEvidenceAdmissionTests(unittest.TestCase):
    def test_actual_result_summary_requires_all_nine_without_skip_or_expected_failure(self):
        summary = {'totalTestCount': 9, 'passedTests': 9, 'failedTests': 0,
                   'skippedTests': 0, 'expectedFailures': 0}
        probe.validate_summary(summary)
        for key, value in [('totalTestCount', 8), ('passedTests', 8), ('failedTests', 1),
                           ('skippedTests', 1), ('expectedFailures', 1), ('totalTestCount', 9.0)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                probe.validate_summary(dict(summary, **{key: value}))

    def test_actual_host_guard_precedes_first_inventory_and_removed_guard_reaches_intercept(self):
        source = Path(probe.__file__).read_text()
        call = '    check_host(args.output.resolve())\n'
        self.assertEqual(source.count(call), 1)
        for removed in [False, True]:
            operations = []

            def intercept(*args, **kwargs):
                operations.append(args)
                raise RuntimeError('Intercepted first inventory; no command ran')

            candidate = source.replace(call, '    pass  # removed guard control\n') if removed else source
            with mock.patch.dict(os.environ, {}, clear=True), \
                 mock.patch.object(sys, 'argv', [probe.__file__, '/tmp/pdf-control/pdf-pagination-probe']), \
                 mock.patch.object(subprocess, 'check_output', intercept):
                with self.assertRaises(RuntimeError) as error:
                    exec(compile(candidate, probe.__file__, 'exec'),
                         {'__file__': probe.__file__, '__name__': '__main__'})
            self.assertEqual(len(operations), 1 if removed else 0)
            self.assertEqual('Intercepted first inventory' in str(error.exception), removed)

    def test_optimized_entry_refuses_before_arguments_source_or_output(self):
        result = subprocess.run([sys.executable, '-B', '-O', probe.__file__],
                                capture_output=True, env={'PATH': os.defpath}, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b'Optimized Python is refused before PDF qualification access', result.stderr)
        self.assertNotIn(b'usage:', result.stderr)

    def test_fixed_simulated_host_accepts_only_same_repository_pull_or_manual_event(self):
        with tempfile.TemporaryDirectory(prefix='mostlytext-pdf-event-control-') as directory:
            event = Path(directory) / 'event.json'
            environment = {'GITHUB_ACTIONS': 'true', 'RUNNER_OS': 'macOS',
                           'GITHUB_REPOSITORY': 'Joncallim/mostlytext',
                           'RUNNER_TEMP': '/Users/runner/work/_temp', 'GITHUB_EVENT_PATH': str(event),
                           'GITHUB_EVENT_NAME': 'pull_request'}
            root = Path('/Users/runner/work/_temp/pdf-pagination-probe')
            # Match the actual POSIX record shape with the public disposable fixture identity.
            account = pwd.struct_passwd(('runner', '*', 501, 20, 'Hosted fixture', '/Users/runner', '/usr/bin/false'))
            with mock.patch.dict(os.environ, environment, clear=True), \
                 mock.patch.object(os, 'getuid', return_value=501), \
                 mock.patch.object(os, 'geteuid', return_value=501), \
                 mock.patch.object(pwd, 'getpwuid', return_value=account), \
                 mock.patch.object(Path, 'home', return_value=Path('/Users/runner')), \
                 mock.patch.object(platform, 'machine', return_value='arm64'), \
                 mock.patch.object(platform, 'mac_ver', return_value=('26.0', (), '')), \
                 mock.patch.object(os.path, 'lexists', return_value=False):
                event.write_text(json.dumps({'pull_request': {'head': {'repo': {'full_name': 'Joncallim/mostlytext'}}}}))
                probe.check_host(root)
                event.write_text(json.dumps({'pull_request': {'head': {'repo': {'full_name': 'untrusted/fork'}}}}))
                with self.assertRaises(RuntimeError):
                    probe.check_host(root)
                event.write_text('{}')
                with mock.patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'push'}), self.assertRaises(RuntimeError):
                    probe.check_host(root)
                with mock.patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'workflow_dispatch'}):
                    probe.check_host(root)
                with self.assertRaises(RuntimeError):
                    probe.check_host(root.parent / 'other')
                with mock.patch.object(os.path, 'lexists', return_value=True), self.assertRaises(RuntimeError):
                    probe.check_host(root)


if __name__ == '__main__':
    if sys.flags.optimize:
        raise RuntimeError('Run PDF refusal controls normally')
    unittest.main()

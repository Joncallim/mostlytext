#!/usr/bin/env python3
"""Bind the complete real PDF adapter selection to exact hosted Release inputs."""
import argparse
import hashlib
import json
import os
import platform
import pwd
from pathlib import Path
import re
import subprocess
import sys

from preview_compiled_inputs import capture, require_owned_phase, verify

TESTS = {
    'vectorSnapshotIsPaginatedWithoutLosingSelectableText',
    'vectorSnapshotMovesAnIntersectedHeadingToTheNextPage',
    'printDestinationIsConfiguredBeforeTheOperationStarts',
    'contentlessPDFIsRejectedForNonemptyDocument',
    'graphicsSetupAndEmptyTextDoNotCountAsPrintedContent',
    'visibleTextAndVectorOnlyDiagramCountAsPrintedContent',
    'hardenedHTMLRetainsThePDFPolicy',
    'aCancelledNavigationDoesNotWaitForWebKitOrTheThirtySecondWatchdog',
    'aCancelledPrintResultPreservesTheExistingDestination',
    'exportingALongDocumentProducesARealMultiPagePDF',
    'exportedPDFReplacesAnyExistingFileAtomically',
}
TEMP_TEST = 'exportingHTMLThenPDFPreservesSourceAndPublishesPDF'
MODAL_PRODUCTION_TEST = 'ordinaryAdapterPrintsWhileMainRunLoopAdvances'
CONDITION = 'PDF_PAGINATION_PROBE'
INPUTS = ['MacDown2', '.github/scripts/verify-pdf-pagination-probe.py',
          '.github/scripts/test-pdf-pagination-probe.py',
          '.github/workflows/pdf-pagination-probe.yml',
          '.github/scripts/run-owned-app-tests.py',
          '.github/scripts/test-run-owned-app-tests.py',
          '.github/scripts/preview_compiled_inputs.py',
          '.github/scripts/test-preview-compiled-inputs.py',
          'planning/downstream/evidence/actual-app-hosted-plan-2026-11-07']


def validate_execution(log, identity, status):
    log = re.sub(r'\x1b\[[0-9;]*m', '', log)
    if any(value in log for value in ['recorded an issue', 'Program crashed:', 'Fatal error:', 'Assertion failed:']):
        raise ValueError('The genuine PDF selection recorded a failure')
    if re.search(r'(?:Test|Suite)[^\n]*(?:skipped|disabled)', log, re.I):
        raise ValueError('A required PDF test was skipped or disabled')
    passed = re.findall(r'Test ([A-Za-z0-9_]+)\([^\n]*\) passed', log)
    if set(passed) != TESTS or len(passed) != len(TESTS):
        raise ValueError('Every PDF adapter function must execute once and pass')
    if not re.search(r'Test run with 11 tests in 2 suites passed', log):
        raise ValueError('The complete eleven-function PDF selection did not pass')
    if not re.search(r'Suite PDFExportAdapterTests passed', log):
        raise ValueError('The actual PDF adapter suite did not pass')
    if not re.search(r'Suite PDFExportCancellationTests passed', log):
        raise ValueError('The PDF cancellation suite did not pass')
    if status.get('returncode') != 0 or status.get('timed_out') is not False or status.get('cancelled') is not False:
        raise ValueError('The owned PDF execution did not exit normally')
    if not 0 < status.get('elapsed_seconds', 0) < 600 or status.get('app_cleanup_requested') != []:
        raise ValueError('The owned PDF execution exceeded its unchanged bound or required cleanup')
    command = identity.get('command', [])
    if not command or command[0] != 'xcodebuild' or 'test-without-building' not in command:
        raise ValueError('Actual app test execution is required')
    if '-configuration' not in command or command[command.index('-configuration') + 1] != 'Release':
        raise ValueError('Release execution is required')
    if 'ENABLE_TESTABILITY=YES' not in command or not any(
        c.startswith('SWIFT_ACTIVE_COMPILATION_CONDITIONS=') and {CONDITION, "RELEASE_PREVIEW_PROBE"} <= set(c.split()) for c in command
    ):
        raise ValueError('The dedicated PDF opt-in condition is required')
    selected = [c for c in command if c.startswith('-only-testing:')]
    if selected != ['-only-testing:MacDown2Tests/PDFExportAdapterTests',
                    '-only-testing:MacDown2Tests/PDFExportCancellationTests']:
        raise ValueError('Both complete PDF suites must be selected')
    if not str(identity.get('app', '')).endswith('/Release/MacDown2.app/Contents/MacOS/MacDown2'):
        raise ValueError('The actual built Release app must own execution')
    if not re.fullmatch(r'[0-9a-f]{64}', identity.get('app_sha256', '')):
        raise ValueError('The actual app digest is required')


def validate_single_execution(log, identity, status, test, suite, conditions, suite_label=None):
    log = re.sub(r'\x1b\[[0-9;]*m', '', log)
    if any(value in log for value in ['recorded an issue', 'Program crashed:', 'Fatal error:', 'Assertion failed:']):
        raise ValueError('The selected PDF run recorded a failure')
    if re.search(r'(?:Test|Suite)[^\n]*(?:skipped|disabled)', log, re.I):
        raise ValueError('The selected PDF test was skipped or disabled')
    passed = re.findall(r'Test ([A-Za-z0-9_]+)\([^\n]*\) passed', log)
    if passed != [test] or not re.search(r'Test run with 1 test in 1 suite passed', log):
        raise ValueError('The complete single PDF test must execute once and pass')
    displayed_suite = f'"{suite_label}"' if suite_label else suite
    if not re.search(rf'Suite {re.escape(displayed_suite)} passed', log):
        raise ValueError('The selected PDF suite did not pass')
    if status.get('returncode') != 0 or status.get('timed_out') is not False or status.get('cancelled') is not False:
        raise ValueError('The owned selected PDF execution did not exit normally')
    if not 0 < status.get('elapsed_seconds', 0) < 600 or status.get('app_cleanup_requested') != []:
        raise ValueError('The selected PDF execution exceeded its bound or required cleanup')
    command = identity.get('command', [])
    if not command or command[0] != 'xcodebuild' or 'test-without-building' not in command:
        raise ValueError('Actual app test execution is required')
    if '-configuration' not in command or command[command.index('-configuration') + 1] != 'Release':
        raise ValueError('Release execution is required')
    if 'ENABLE_TESTABILITY=YES' not in command or not any(
        c.startswith('SWIFT_ACTIVE_COMPILATION_CONDITIONS=') and conditions <= set(c.split())
        for c in command
    ):
        raise ValueError('The dedicated PDF opt-in condition is required')
    if [c for c in command if c.startswith('-only-testing:')] != [f'-only-testing:MacDown2Tests/{suite}']:
        raise ValueError('Only the complete selected PDF suite may be selected')
    if not str(identity.get('app', '')).endswith('/Release/MacDown2.app/Contents/MacOS/MacDown2'):
        raise ValueError('The actual built Release app must own execution')
    if not re.fullmatch(r'[0-9a-f]{64}', identity.get('app_sha256', '')):
        raise ValueError('The actual app digest is required')


def validate_temp_execution(log, identity, status):
    validate_single_execution(log, identity, status, TEMP_TEST, 'PDFExportTemporaryDestinationTests',
                              {CONDITION, 'RELEASE_PREVIEW_PROBE'},
                              suite_label='PDF export after HTML in a private temporary folder')


def validate_modal_production_execution(log, identity, status):
    validate_single_execution(log, identity, status, MODAL_PRODUCTION_TEST, 'PDFModalProductionPathTests',
                              {CONDITION, 'PDF_MODAL_PROBE', 'RELEASE_PREVIEW_PROBE'})
    measurements = re.findall(r'pdf-production-modal-print elapsed_ms=([0-9.]+) main_run_loop_heartbeats=([0-9]+)', log)
    if len(measurements) != 1:
        raise ValueError('The production PDF print interval lacks one heartbeat measurement')
    elapsed, heartbeats = measurements[0]
    if not 0 < float(elapsed) < 600_000 or int(heartbeats) < 1:
        raise ValueError('The production PDF print interval did not retain a bounded live run loop')
    if log.count('pdf-production-modal-revocation preserved_existing_destination=true') != 1:
        raise ValueError('The production PDF print did not prove revoked publication preserves its destination')


def check_host(root):
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python is refused before PDF qualification access')
    if (os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'):
        raise RuntimeError('PDF qualification requires the disposable hosted repository context')
    account = pwd.getpwuid(os.getuid())
    if (os.getuid() != os.geteuid() or os.getuid() <= 0 or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or Path.home() != Path('/Users/runner')
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or str(root) != '/Users/runner/work/_temp/pdf-pagination-probe'
            or root != Path(os.environ.get('RUNNER_TEMP', '')).resolve() / 'pdf-pagination-probe'
            or any(os.path.lexists(p) for p in ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])):
        raise RuntimeError('PDF qualification host, identity or fixed root is refused')
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if 'pull_request' in event:
        if event['pull_request']['head']['repo']['full_name'] != 'Joncallim/mostlytext':
            raise RuntimeError('Untrusted PDF qualification pull request')
    elif os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        raise RuntimeError('Untrusted PDF qualification event')


def validate_summary(summary, count=11):
    expected = {'totalTestCount': count, 'passedTests': count, 'failedTests': 0,
                'skippedTests': 0, 'expectedFailures': 0}
    if any(type(summary.get(k)) is not int or summary[k] != v for k, v in expected.items()):
        raise ValueError('Actual PDF result bundle lacks the complete passing selection')


def main():
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python is refused before PDF qualification access')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--require-result', action='store_true')
    parser.add_argument('--require-temp-result', action='store_true')
    parser.add_argument('--require-modal-production-result', action='store_true')
    parser.add_argument('--capture-compiled', action='store_true')
    parser.add_argument('--admit', action='store_true')
    args = parser.parse_args()
    check_host(args.output.resolve())
    if args.admit:
        if (args.verify or args.require_result or args.require_temp_result
                or args.require_modal_production_result or args.capture_compiled):
            raise RuntimeError('Host admission cannot select another PDF phase')
        return
    if (args.require_result or args.require_temp_result or args.require_modal_production_result
            or args.capture_compiled) and not args.verify:
        raise RuntimeError('Compiled/result PDF phases require original input verification')
    repo = Path(__file__).resolve().parents[2]
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--', *INPUTS], cwd=repo).decode().split('\0')
    pins = json.loads((repo / 'MacDown2/Packages/MacDownKit/Package.resolved').read_text())['pins']
    if len(pins) != len({p['identity'] for p in pins}) or len(pins) != 24:
        raise SystemExit('The exact canonical 24-pin graph is required')
    receipt = {
        'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
        'configuration': 'Release', 'testability': True,
        'additional_compilation_conditions': ['RELEASE_PREVIEW_PROBE', CONDITION, 'PDF_MODAL_PROBE'],
        'source_sha256': {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths if p},
        'pins': pins, 'selected_tests': sorted(TESTS),
        'scope': 'Actual hosted PDF output and controlled cancellation checkpoints; not owner UI, mid-print interruption or signed-RC acceptance',
    }
    path = args.output / 'receipt.json'
    if args.verify:
        if json.loads(path.read_text()) != receipt:
            raise SystemExit('PDF qualification source, configuration or pins changed')
        if args.require_result:
            identity = json.loads((args.output / 'diagnostics/identity.json').read_text())
            if identity.get('checkout') != receipt['checkout']:
                raise SystemExit('The actual app execution checkout differs')
            validate_execution((args.output / 'probe.log').read_text(), identity,
                               json.loads((args.output / 'diagnostics/status.json').read_text()))
            binding = json.loads((args.output / 'compiled-initial.json').read_text())
            if binding['phase'] != 'initial' or binding['configuration'] != 'Release':
                raise RuntimeError('PDF compiled phase was retargeted')
            verify(args.output, binding)
            require_owned_phase(identity, binding, receipt['checkout'])
            raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                           '--path', str(args.output / 'actual-pdf.xcresult')])
            (args.output / 'actual-pdf-summary.json').write_bytes(raw)
            validate_summary(json.loads(raw))
        if args.require_temp_result:
            identity = json.loads((args.output / 'temp-diagnostics/identity.json').read_text())
            if identity.get('checkout') != receipt['checkout']:
                raise SystemExit('The private-folder PDF execution checkout differs')
            validate_temp_execution((args.output / 'temp-destination.log').read_text(), identity,
                                    json.loads((args.output / 'temp-diagnostics/status.json').read_text()))
            binding = json.loads((args.output / 'compiled-initial.json').read_text())
            if binding['phase'] != 'initial' or binding['configuration'] != 'Release':
                raise RuntimeError('PDF compiled phase was retargeted')
            verify(args.output, binding)
            require_owned_phase(identity, binding, receipt['checkout'])
            raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                           '--path', str(args.output / 'temp-destination.xcresult')])
            (args.output / 'temp-destination-summary.json').write_bytes(raw)
            validate_summary(json.loads(raw), count=1)
        if args.require_modal_production_result:
            identity = json.loads((args.output / 'production-modal-diagnostics/identity.json').read_text())
            if identity.get('checkout') != receipt['checkout']:
                raise SystemExit('The production modal PDF execution checkout differs')
            validate_modal_production_execution((args.output / 'production-modal.log').read_text(), identity,
                                                json.loads((args.output / 'production-modal-diagnostics/status.json').read_text()))
            binding = json.loads((args.output / 'compiled-initial.json').read_text())
            if binding['phase'] != 'initial' or binding['configuration'] != 'Release':
                raise RuntimeError('PDF compiled phase was retargeted')
            verify(args.output, binding)
            require_owned_phase(identity, binding, receipt['checkout'])
            raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                           '--path', str(args.output / 'production-modal.xcresult')])
            (args.output / 'production-modal-summary.json').write_bytes(raw)
            validate_summary(json.loads(raw), count=1)
        if args.capture_compiled:
            capture(args.output, Path(os.environ['RUNNER_TEMP']) / 'pdf-pagination-app/Build/Products',
                    'Release', repo / 'MacDown2/MacDown2.xcodeproj', 'initial')
        print('Exact PDF inputs, configuration, pins and requested execution verified')
    else:
        args.output.mkdir(parents=True, exist_ok=True)
        with path.open('x') as output:
            json.dump(receipt, output, indent=2)
            output.write('\n')
        print('Recorded actual PDF source and pins; execution remains unverified')


if __name__ == '__main__':
    main()

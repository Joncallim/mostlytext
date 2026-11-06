#!/usr/bin/env python3
"""Bind the complete real PDF adapter selection to exact hosted Release inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

TESTS = {
    'vectorSnapshotIsPaginatedWithoutLosingSelectableText',
    'vectorSnapshotMovesAnIntersectedHeadingToTheNextPage',
    'printDestinationIsConfiguredBeforeTheOperationStarts',
    'contentlessPDFIsRejectedForNonemptyDocument',
    'graphicsSetupAndEmptyTextDoNotCountAsPrintedContent',
    'visibleTextAndVectorOnlyDiagramCountAsPrintedContent',
    'hardenedHTMLRetainsThePDFPolicy',
    'exportingALongDocumentProducesARealMultiPagePDF',
    'exportedPDFReplacesAnyExistingFileAtomically',
}
CONDITION = 'PDF_PAGINATION_PROBE'
INPUTS = ['MacDown2', '.github/scripts/verify-pdf-pagination-probe.py',
          '.github/scripts/test-pdf-pagination-probe.py',
          '.github/workflows/pdf-pagination-probe.yml',
          '.github/scripts/run-owned-app-tests.py',
          '.github/scripts/test-run-owned-app-tests.py']


def validate_execution(log, identity, status):
    log = re.sub(r'\x1b\[[0-9;]*m', '', log)
    if any(value in log for value in ['recorded an issue', 'Program crashed:', 'Fatal error:', 'Assertion failed:']):
        raise ValueError('The genuine PDF selection recorded a failure')
    if re.search(r'(?:Test|Suite)[^\n]*(?:skipped|disabled)', log, re.I):
        raise ValueError('A required PDF test was skipped or disabled')
    passed = re.findall(r'Test ([A-Za-z0-9_]+)\([^\n]*\) passed', log)
    if set(passed) != TESTS or len(passed) != len(TESTS):
        raise ValueError('Every original PDF function must execute once and pass')
    if not re.search(r'Test run with 9 tests in 1 suite passed', log):
        raise ValueError('The complete nine-function PDF selection did not pass')
    if not re.search(r'Suite PDFExportAdapterTests passed', log):
        raise ValueError('The actual PDF adapter suite did not pass')
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
    if selected != ['-only-testing:MacDown2Tests/PDFExportAdapterTests']:
        raise ValueError('The complete original PDF suite must be selected')
    if not str(identity.get('app', '')).endswith('/Release/MacDown2.app/Contents/MacOS/MacDown2'):
        raise ValueError('The actual built Release app must own execution')
    if not re.fullmatch(r'[0-9a-f]{64}', identity.get('app_sha256', '')):
        raise ValueError('The actual app digest is required')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--require-result', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--', *INPUTS], cwd=repo).decode().split('\0')
    pins = json.loads((repo / 'MacDown2/Packages/MacDownKit/Package.resolved').read_text())['pins']
    if len(pins) != len({p['identity'] for p in pins}) or len(pins) != 24:
        raise SystemExit('The exact canonical 24-pin graph is required')
    receipt = {
        'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
        'configuration': 'Release', 'testability': True, 'additional_compilation_conditions': ['RELEASE_PREVIEW_PROBE', CONDITION],
        'source_sha256': {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in paths if p},
        'pins': pins, 'selected_tests': sorted(TESTS),
        'scope': 'Actual hosted PDF adapter output; not owner UI, print cancellation or signed-RC acceptance',
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
        print('Exact PDF inputs, configuration, pins and requested execution verified')
    else:
        args.output.mkdir(parents=True, exist_ok=True)
        with path.open('x') as output:
            json.dump(receipt, output, indent=2)
            output.write('\n')
        print('Recorded actual PDF source and pins; execution remains unverified')


if __name__ == '__main__':
    main()

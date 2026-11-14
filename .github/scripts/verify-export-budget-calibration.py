#!/usr/bin/env python3
"""Bind a hosted export measurement to the actual Release app and five cases."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import pwd
import re
import subprocess
import sys


FILES = [
    'MacDown2/MacDown2Tests/ExportBudgetCalibrationTests.swift',
    'MacDown2/MacDown2/PDFExportAdapter.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportResourceBudget.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportComposer.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportHTMLWriter.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportResourceSlots.swift',
    'MacDown2/Packages/MacDownKit/Package.resolved',
    'MacDown2/project.yml',
    '.github/scripts/sample-export-budget-memory.py',
    '.github/scripts/test-sample-export-budget-memory.py',
    '.github/scripts/verify-export-budget-calibration.py',
    '.github/scripts/run-owned-app-tests.py',
    '.github/workflows/export-budget-calibration.yml',
]
TESTS = {'repeatedImageHTMLUsesActualExportService', 'realWebKitPrintAndPDFKitReadback',
         'scaledWebKitPrintAndPDFKitReadback', 'nearPageLimitWebKitPrintAndPDFKitReadback',
         'oversizedSourceIsRefusedBeforePublication'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_host(root):
    account = pwd.getpwuid(os.getuid())
    expected = Path(os.environ.get('RUNNER_TEMP', '')) / 'export-budget-calibration'
    if (sys.flags.optimize or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.getuid() != os.geteuid() or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or Path.home() != Path('/Users/runner')
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or root != expected or any(os.path.lexists(p) for p in
                                    ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])):
        raise RuntimeError('Refuse export measurement outside the owned disposable hosted runner')
    event_name = os.environ.get('GITHUB_EVENT_NAME')
    if event_name == 'pull_request':
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        if event['pull_request']['head']['repo']['full_name'] != 'Joncallim/mostlytext':
            raise RuntimeError('Refuse a forked export calibration request')
    elif event_name != 'workflow_dispatch':
        raise RuntimeError('Refuse an unexpected export calibration trigger')


def source_receipt(repo):
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo):
        raise RuntimeError('Export calibration requires a clean checkout')
    pins = json.loads((repo / 'MacDown2/Packages/MacDownKit/Package.resolved').read_text())['pins']
    if len(pins) != 24 or len({row['identity'] for row in pins}) != len(pins):
        raise RuntimeError('The current immutable 24-pin graph is required')
    xcode = subprocess.check_output(['xcodebuild', '-version'], text=True).splitlines()
    if not xcode or xcode[0] != 'Xcode 26.6':
        raise RuntimeError('The selected Xcode differs from the measured toolchain')
    return {'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'xcode': xcode, 'macos': platform.mac_ver()[0], 'configuration': 'Release',
            'source_sha256': {name: digest(repo / name) for name in FILES}, 'pins': pins,
            'selected_tests': sorted(TESTS),
            'scope': 'Exploratory actual-path Release measurement; no budget is frozen or release accepted'}


def positive_number(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def validate_records(root):
    records = {name: json.loads((root / 'measurements' / (name + '.json')).read_text())
               for name in ['html', 'pdf', 'scaled-pdf', 'near-page-limit-pdf', 'refusal']}
    html, pdf, scaled, refusal = (records[name] for name in ['html', 'pdf', 'scaled-pdf', 'refusal'])
    near = records['near-page-limit-pdf']
    if (html.get('case') != 'actual-self-contained-html' or html.get('resource_occurrences') != 2048
            or pdf.get('case') != 'actual-webkit-print-pdfkit'
            or scaled.get('case') != 'actual-scaled-webkit-print-pdfkit'
            or scaled.get('sections') != 200
            or near.get('case') != 'actual-scaled-webkit-print-pdfkit'
            or near.get('sections') != 460
            or refusal.get('case') != 'actual-source-cap-plus-one-refusal'
            or refusal.get('source_bytes') != (32 << 20) + 1 or refusal.get('output_exists') is not False
            or not 0 < html.get('source_bytes', 0) < (32 << 20)
            or not 0 < pdf.get('source_bytes', 0) < (32 << 20)
            or not 100_000 < scaled.get('source_bytes', 0) < (32 << 20)
            or not 600_000 < near.get('source_bytes', 0) < (32 << 20)
            or not 0 < html.get('output_bytes', 0) <= (256 << 20)
            or not 0 < pdf.get('prepared_html_bytes', 0) <= (256 << 20)
            or not 0 < pdf.get('pdf_bytes', 0) <= (256 << 20)
            or not 0 < scaled.get('prepared_html_bytes', 0) <= (256 << 20)
            or not 0 < scaled.get('pdf_bytes', 0) <= (256 << 20)
            or not 0 < near.get('prepared_html_bytes', 0) <= (256 << 20)
            or not 0 < near.get('pdf_bytes', 0) <= (256 << 20)
            or not 1 < pdf.get('page_count', 0) <= 1024
            or not 20 <= scaled.get('page_count', 0) <= 256
            or not 200 <= near.get('page_count', 0) <= 256):
        raise RuntimeError('Actual HTML, PDF or refusal result is missing or inconsistent')
    for name, row in records.items():
        if (not positive_number(row.get('app_peak_rss_bytes'))
                or not re.fullmatch(r'[0-9a-f]{64}', row.get('source_sha256', ''))
                or not positive_number(row.get('source_bytes'))):
            raise RuntimeError(name + ' lacks exact source and process evidence')
        duration_fields = {'html': ['elapsed_seconds'], 'pdf': ['prepare_seconds', 'print_and_validation_seconds'],
                           'scaled-pdf': ['prepare_seconds', 'print_and_validation_seconds'],
                           'near-page-limit-pdf': ['prepare_seconds', 'print_and_validation_seconds'],
                           'refusal': ['elapsed_seconds']}[name]
        if any(not positive_number(row.get(field)) for field in duration_fields):
            raise RuntimeError(name + ' lacks a positive bounded timing')
    for name in ['scaled-pdf', 'near-page-limit-pdf']:
        row = records[name]
        if (not positive_number(row.get('app_peak_before_rss_bytes'))
                or row['app_peak_rss_bytes'] < row['app_peak_before_rss_bytes']):
            raise RuntimeError(name + ' lacks a valid app high-water comparison')
        retained = root / 'measurements' / (name + '-output.pdf')
        if (not retained.is_file() or retained.stat().st_size != row['pdf_bytes']
                or digest(retained) != row['pdf_sha256']
                or not positive_number(row.get('extracted_text_bytes'))
                or type(row.get('page_text_bytes')) is not list
                or len(row['page_text_bytes']) != row['page_count']
                or any(type(value) is not int or value < 0 for value in row['page_text_bytes'])
                or sum(row['page_text_bytes']) == 0):
            raise RuntimeError(name + ' artifact or per-page text evidence is incomplete')
    kinds = near.get('raw_source_kinds')
    if (type(kinds) is not list or not kinds or len(kinds) != len(set(kinds))
            or not set(kinds) <= {'print', 'snapshot'}):
        raise RuntimeError('No qualified pre-pagination PDF source was captured')
    for kind in kinds:
        raw = root / 'measurements' / f'near-page-limit-raw-{kind}.pdf'
        if (not raw.is_file() or raw.stat().st_size != near.get(f'raw_{kind}_pdf_bytes')
                or digest(raw) != near.get(f'raw_{kind}_pdf_sha256')
                or not 0 < near.get(f'raw_{kind}_page_count', 0) <= 256):
            raise RuntimeError(kind + ' pre-pagination PDF is not bound to the larger print result')
    for row, field in [(html, 'output_sha256'), (pdf, 'pdf_sha256'),
                       (scaled, 'pdf_sha256'), (near, 'pdf_sha256')]:
        if not re.fullmatch(r'[0-9a-f]{64}', row.get(field, '')):
            raise RuntimeError('A produced export lacks a digest')
    return records


def validate_execution(root, receipt):
    identity = json.loads((root / 'diagnostics/identity.json').read_text())
    status = json.loads((root / 'diagnostics/status.json').read_text())
    monitor = json.loads((root / 'memory/summary.json').read_text())
    if (identity.get('checkout') != receipt['checkout'] or status.get('returncode') != 0
            or status.get('timed_out') is not False or status.get('cancelled') is not False
            or status.get('app_cleanup_requested') != []
            or monitor.get('command_returncode') != 0 or monitor.get('timed_out') is not False
            or monitor.get('cancelled') is not False or not 0 < status.get('elapsed_seconds', 0) < 600
            or not 0 < monitor.get('elapsed_seconds', 0) < 650
            or not positive_number(monitor.get('peak_app_sampled_rss_bytes'))
            or not positive_number(monitor.get('peak_new_webkit_sampled_rss_bytes'))):
        raise RuntimeError('The bounded actual app/WebKit execution or memory sample is incomplete')
    command = identity.get('command', [])
    expected = ['-only-testing:MacDown2Tests/ExportBudgetCalibrationTests']
    if (not command or command[0] != 'xcodebuild' or 'test-without-building' not in command
            or [part for part in command if part.startswith('-only-testing:')] != expected
            or '-configuration' not in command
            or command[command.index('-configuration') + 1] != 'Release'
            or 'ENABLE_TESTABILITY=YES' not in command
            or not any(part.startswith('SWIFT_ACTIVE_COMPILATION_CONDITIONS=')
                       and 'EXPORT_BUDGET_PROBE' in part.split() for part in command)):
        raise RuntimeError('The real Release calibration selection was retargeted')
    app = Path(identity.get('app', ''))
    if (not str(app).endswith('/Release/MacDown2.app/Contents/MacOS/MacDown2')
            or not app.is_file() or digest(app) != identity.get('app_sha256')):
        raise RuntimeError('The measured app executable differs from the built one')
    log = re.sub(r'\x1b\[[0-9;]*m', '', (root / 'probe.log').read_text())
    if any(marker in log for marker in ['recorded an issue', 'Program crashed:', 'Fatal error:']):
        raise RuntimeError('The actual test log records a failure')
    passed = re.findall(r'Test ([A-Za-z0-9_]+)\([^\n]*\) passed', log)
    if set(passed) != TESTS or len(passed) != len(TESTS):
        raise RuntimeError('Every actual calibration test must pass exactly once')
    result = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                                 '--path', str(root / 'actual-export.xcresult')]))
    (root / 'actual-export-summary.json').write_text(json.dumps(result, indent=2) + '\n')
    expected_counts = {'totalTestCount': 5, 'passedTests': 5, 'failedTests': 0,
                       'skippedTests': 0, 'expectedFailures': 0}
    if any(type(result.get(key)) is not int or result[key] != value for key, value in expected_counts.items()):
        raise RuntimeError('Actual xcresult does not contain five complete passing functions')
    return validate_records(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--prepare', action='store_true')
    args = parser.parse_args()
    check_host(args.root)
    repo = Path(__file__).resolve().parents[2]
    receipt = source_receipt(repo)
    path = args.root / 'receipt.json'
    if args.prepare:
        args.root.mkdir(parents=True, exist_ok=False)
        path.write_text(json.dumps(receipt, indent=2) + '\n')
        return
    if json.loads(path.read_text()) != receipt:
        raise RuntimeError('Source, toolchain, pins or selected tests changed during the run')
    records = validate_execution(args.root, receipt)
    print('Actual Release export measurements verified:', ', '.join(sorted(records)))


if __name__ == '__main__':
    main()

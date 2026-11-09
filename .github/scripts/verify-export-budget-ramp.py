#!/usr/bin/env python3
"""Verify exact hosted Release export ramp sources, fixtures and per-case receipts."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import pwd
import re
import runpy
import subprocess
import sys


FILES = [
    'MacDown2/MacDown2Tests/ExportBudgetRampTests.swift',
    'MacDown2/MacDown2/PDFExportAdapter.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportResourceBudget.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportComposer.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportHTMLWriter.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportResourceSlots.swift',
    'MacDown2/Packages/MacDownKit/Sources/ExportService/ExportResourceResolver.swift',
    'MacDown2/Packages/MacDownKit/Package.resolved',
    'MacDown2/project.yml',
    '.github/scripts/prepare-export-budget-ramp.py',
    '.github/scripts/run-export-budget-ramp.py',
    '.github/scripts/test-export-budget-ramp.py',
    '.github/scripts/verify-export-budget-ramp.py',
    '.github/scripts/run-owned-app-tests.py',
    '.github/workflows/export-budget-ramp.yml',
]
MIB = 1 << 20


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(MIB), b''):
            result.update(block)
    return result.hexdigest()


def check_host(root):
    account = pwd.getpwuid(os.getuid())
    expected = Path(os.environ.get('RUNNER_TEMP', '')) / 'export-budget-ramp'
    if (sys.flags.optimize or root != expected or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.getuid() != os.geteuid() or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or Path.home() != Path('/Users/runner')
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or any(os.path.lexists(path) for path in
                   ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])):
        raise RuntimeError('Refuse export ramp verification outside the owned hosted runner')
    event = os.environ.get('GITHUB_EVENT_NAME')
    if event == 'pull_request':
        payload = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        if payload['pull_request']['head']['repo']['full_name'] != 'Joncallim/mostlytext':
            raise RuntimeError('Refuse a forked export ramp request')
    elif event != 'workflow_dispatch':
        raise RuntimeError('Unexpected export ramp trigger')


def source_receipt(repo):
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo):
        raise RuntimeError('Export ramp requires a clean checkout')
    pins = json.loads((repo / 'MacDown2/Packages/MacDownKit/Package.resolved').read_text())['pins']
    if len(pins) != 24 or len({row['identity'] for row in pins}) != 24:
        raise RuntimeError('The immutable 24-pin graph changed')
    xcode = subprocess.check_output(['xcodebuild', '-version'], text=True).splitlines()
    if not xcode or xcode[0] != 'Xcode 26.6':
        raise RuntimeError('The selected Xcode differs from the measured toolchain')
    return {
        'checkout': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
        'xcode': xcode, 'macos': platform.mac_ver()[0], 'configuration': 'Release',
        'source_sha256': {name: digest(repo / name) for name in FILES}, 'pins': pins,
        'scope': 'Private exploratory actual-path Release ramp; no ceiling is frozen or release accepted',
    }


def fixture_receipt(root, generator):
    fixture = root / 'fixtures'
    manifest = json.loads((fixture / 'fixture-manifest.json').read_text())
    order = tuple(manifest.get('case_order', []))
    if (manifest.get('schema') != 1 or order != generator['CASE_ORDER']
            or set(manifest.get('assets', {})) != set(generator['ASSET_SIZES'])
            or set(manifest.get('cases', {})) != set(order)):
        raise RuntimeError('Fixture manifest differs from fixed case ladder')
    files = {}
    for name, size in generator['ASSET_SIZES'].items():
        path = fixture / 'assets' / (name + '.png')
        generator['assert_png'](path)
        if (path.stat().st_size != size or manifest['assets'][name] !=
                {'bytes': size, 'sha256': digest(path)}):
            raise RuntimeError(name + ' image size, CRC or digest changed')
        files[str(path.relative_to(fixture))] = manifest['assets'][name]['sha256']
    distinct_hashes = {manifest['assets'][f'count{index:03d}']['sha256'] for index in range(513)}
    if len(distinct_hashes) != 513:
        raise RuntimeError('The resource-count ladder did not create 513 distinct image identities')
    for name in order:
        row = manifest['cases'][name]
        expected = generator['case_definition'](name)
        if any(row.get(key) != value for key, value in expected.items()):
            raise RuntimeError(name + ' expected budget case changed')
        folder = fixture / 'cases' / name
        source = folder / 'source.md'
        source_digest = digest(source)
        if expected['mode'] == 'html' and source.read_text() != generator['html_source'](name, expected):
            raise RuntimeError(name + ' authored image reference sequence changed')
        if (row.get('source_bytes') != source.stat().st_size
                or row.get('source_sha256') != source_digest
                or row.get('resource_bytes') != sum(manifest['assets'][key]['bytes']
                                                    for key in expected['assets'].values())
                or row.get('asset_sha256') != {filename: manifest['assets'][key]['sha256']
                                               for filename, key in expected['assets'].items()}
                or json.loads((folder / 'manifest.json').read_text()) != row):
            raise RuntimeError(name + ' source or resource receipt changed')
        files[str(source.relative_to(fixture))] = source_digest
        for filename, key in expected['assets'].items():
            path = folder / filename
            if not path.is_file() or not os.path.samefile(path, fixture / 'assets' / (key + '.png')):
                raise RuntimeError(name + ' resource is not the pinned fixture hard link')
    return {'manifest_sha256': digest(fixture / 'fixture-manifest.json'), 'files_sha256': files,
            'case_order': list(order)}


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def verify_case(root, name, row, source, app):
    case = root / 'cases' / name
    identity = json.loads((case / 'diagnostics' / 'identity.json').read_text())
    status = json.loads((case / 'diagnostics' / 'status.json').read_text())
    memory = json.loads((case / 'memory.json').read_text())
    result = json.loads((case / 'measurements' / 'result.json').read_text())
    inspection = json.loads((case / 'output-inspection.json').read_text())
    if (identity.get('checkout') != source['checkout'] or identity.get('app') != str(app)
            or identity.get('app_sha256') != digest(app)
            or status.get('returncode') != 0 or status.get('timed_out') is not False
            or status.get('cancelled') is not False or status.get('app_cleanup_requested') != []
            or memory.get('case') != name or memory.get('command_returncode') != 0
            or memory.get('guard_reason') is not None or not positive(memory.get('elapsed_seconds'))
            or memory['elapsed_seconds'] >= 180
            or not positive(memory.get('peak_app_sampled_rss_bytes'))
            or memory['peak_app_sampled_rss_bytes'] >= memory.get('cohort_rss_ceiling_bytes', 0)
            or memory.get('sample_count', 0) < 1):
        raise RuntimeError(name + ' owned app, time or memory receipt is incomplete')
    command = identity.get('command', [])
    if (not command or command[0] != 'xcodebuild' or 'test-without-building' not in command
            or [part for part in command if part.startswith('-only-testing:')] !=
            ['-only-testing:MacDown2Tests/ExportBudgetRampTests']
            or '-configuration' not in command or command[command.index('-configuration') + 1] != 'Release'
            or 'ENABLE_TESTABILITY=YES' not in command
            or not any(part.startswith('SWIFT_ACTIVE_COMPILATION_CONDITIONS=')
                       and 'EXPORT_BUDGET_RAMP_PROBE' in part.split() for part in command)):
        raise RuntimeError(name + ' Release test selection changed')
    log = re.sub(r'\x1b\[[0-9;]*m', '', (case / 'probe.log').read_text())
    if (any(marker in log for marker in ['recorded an issue', 'Program crashed:', 'Fatal error:'])
            or len(re.findall(r'Test selectedCase\([^\n]*\) passed', log)) != 1):
        raise RuntimeError(name + ' test transcript is missing a single pass')
    summary = json.loads(subprocess.check_output(
        ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(case / 'test.xcresult')]))
    (case / 'test-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    counts = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0,
              'skippedTests': 0, 'expectedFailures': 0}
    if any(type(summary.get(key)) is not int or summary[key] != count for key, count in counts.items()):
        raise RuntimeError(name + ' xcresult is not exactly one passing test')
    if (result.get('case') != name or result.get('source_bytes') != row['source_bytes']
            or result.get('resource_bytes') != row['resource_bytes']
            or result.get('occurrences') != row['occurrences']
            or not positive(result.get('app_peak_before_bytes'))
            or not positive(result.get('app_peak_after_bytes'))):
        raise RuntimeError(name + ' measured app record differs from fixture')
    if row['refusal']:
        if (result.get('outcome') != 'budget-refusal' or result.get('output_exists') is not False
                or result.get('refusal_kind') != row['refusal_kind']
                or inspection != {'outcome': 'budget-refusal', 'output_exists': False}
                or (case / 'export.html').exists() or not positive(result.get('elapsed_seconds'))):
            raise RuntimeError(name + ' did not produce a clean budget refusal')
    else:
        if (result.get('outcome') != 'published' or inspection.get('outcome') != 'published'
                or result.get('output_bytes') != inspection.get('output_bytes')
                or result.get('output_sha256') != inspection.get('output_sha256')
                or not re.fullmatch(r'[0-9a-f]{64}', result.get('output_sha256', ''))
                or not 0 < result['output_bytes'] <= (256 << 20)
                or not positive(result.get('export_seconds'))
                or not positive(result.get('readback_seconds'))
                or (case / 'export.html').exists()):
            raise RuntimeError(name + ' published output failed independent digest inspection')
        if (result.get('final_html_ceiling_margin_bytes') != (256 << 20) - result['output_bytes']
                or name == 'repeatNearFinal' and result['output_bytes'] < (256 << 20) - (16 << 10)):
            raise RuntimeError(name + ' final HTML size or near-cap boundary is inconsistent')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('phase', choices=['prepare', 'fixtures', 'final'])
    args = parser.parse_args()
    check_host(args.root)
    repo = Path(__file__).resolve().parents[2]
    source = source_receipt(repo)
    source_path = args.root / 'source-receipt.json'
    if args.phase == 'prepare':
        args.root.mkdir(parents=True, exist_ok=False)
        source_path.write_text(json.dumps(source, indent=2) + '\n')
        return
    if json.loads(source_path.read_text()) != source:
        raise RuntimeError('Source, lock or toolchain changed during ramp')
    generator = runpy.run_path(str(repo / '.github/scripts/prepare-export-budget-ramp.py'))
    fixture = fixture_receipt(args.root, generator)
    fixture_path = args.root / 'fixture-receipt.json'
    if args.phase == 'fixtures':
        fixture_path.write_text(json.dumps(fixture, indent=2) + '\n')
        return
    if json.loads(fixture_path.read_text()) != fixture:
        raise RuntimeError('Pinned fixture content changed during ramp')
    app = Path(os.environ['RUNNER_TEMP']) / 'export-budget-ramp-app/Build/Products/Release/MacDown2.app/Contents/MacOS/MacDown2'
    if not app.is_file():
        raise RuntimeError('Built Release app is missing')
    manifest = json.loads((args.root / 'fixtures/fixture-manifest.json').read_text())
    for name in fixture['case_order']:
        verify_case(args.root, name, manifest['cases'][name], source, app)
    summary = json.loads((args.root / 'run-summary.json').read_text())
    if (summary.get('case_order') != fixture['case_order'] or summary.get('case_count') != len(fixture['case_order'])
            or summary.get('outcome') != 'completed'
            or not 0 < summary.get('elapsed_seconds', 0) < 1800):
        raise RuntimeError('The complete ramp exceeded its total time ceiling')
    print('Verified ' + str(len(fixture['case_order'])) + ' actual Release export ramp cases')


if __name__ == '__main__':
    main()

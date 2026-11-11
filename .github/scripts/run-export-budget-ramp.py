#!/usr/bin/env python3
"""Run one fresh owned Release app test per bounded export ramp case."""
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import runpy
import signal
import subprocess
import sys
import time


MIB = 1 << 20
MAX_CASE_SECONDS = 180
MAX_TOTAL_SECONDS = 1800
MAX_COHORT_RSS_BYTES = 1536 * MIB
SAMPLE_SECONDS = 0.5
WEBKIT_HELPERS = {'com.apple.WebKit.WebContent', 'com.apple.WebKit.GPU', 'com.apple.WebKit.Networking'}


def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(MIB), b''):
            hasher.update(block)
    return hasher.hexdigest()


def check_host(root, app):
    account = pwd.getpwuid(os.getuid())
    expected = Path(os.environ.get('RUNNER_TEMP', '')) / 'export-budget-ramp'
    if (sys.flags.optimize or root != expected or not app.is_absolute() or not app.is_file()
            or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.getuid() != os.geteuid() or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or Path.home() != Path('/Users/runner')
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or any(os.path.lexists(path) for path in
                   ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])):
        raise RuntimeError('Refuse an export ramp outside the owned hosted runner')


def processes():
    output = subprocess.check_output(['ps', '-axo', 'pid=,uid=,rss=,comm='], text=True, timeout=10)
    rows = []
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) != 4:
            continue
        try:
            pid, uid, rss_kib = map(int, fields[:3])
        except ValueError:
            continue
        if uid == os.getuid() and pid > 0 and rss_kib >= 0:
            rows.append((pid, rss_kib * 1024, fields[3]))
    return rows


def sample(rows, app, baseline_webkit):
    app_bytes = sum(rss for _, rss, executable in rows if executable == str(app))
    helpers = [(pid, rss) for pid, rss, executable in rows
               if Path(executable).name in WEBKIT_HELPERS and pid not in baseline_webkit]
    return {'app_rss_bytes': app_bytes, 'new_webkit_rss_bytes': sum(rss for _, rss in helpers),
            'new_webkit_processes': len(helpers)}


def app_processes(app):
    return [pid for pid, _, executable in processes() if executable == str(app)]


def guard_reason(elapsed_case, elapsed_total, observation):
    if elapsed_case >= MAX_CASE_SECONDS:
        return 'case-time-ceiling'
    if elapsed_total >= MAX_TOTAL_SECONDS:
        return 'total-time-ceiling'
    if observation['app_rss_bytes'] + observation['new_webkit_rss_bytes'] >= MAX_COHORT_RSS_BYTES:
        return 'cohort-rss-ceiling'
    return None


def terminate_supervisor(process):
    if process.poll() is not None:
        return
    # The owned executor receives SIGTERM and terminates its xcodebuild group.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=35)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=10)


def command_for_case(name, root, app):
    result = root / 'cases' / name
    return [
        'python3', '.github/scripts/run-owned-app-tests.py', str(result / 'diagnostics'), str(app), '--',
        'xcodebuild', '-project', 'MacDown2/MacDown2.xcodeproj', '-scheme', 'MacDown2',
        '-configuration', 'Release', 'ENABLE_TESTABILITY=YES',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) EXPORT_BUDGET_RAMP_PROBE RELEASE_PREVIEW_PROBE',
        '-destination', 'platform=macOS', '-derivedDataPath', str(Path(os.environ['RUNNER_TEMP']) / 'export-budget-ramp-app'),
        '-onlyUsePackageVersionsFromResolvedFile', '-parallel-testing-enabled', 'NO',
        '-resultBundlePath', str(result / 'test.xcresult'),
        '-only-testing:MacDown2Tests/ExportBudgetRampTests', 'test-without-building',
    ]


def inspect_output(case_dir, expected):
    result_path = case_dir / 'measurements' / 'result.json'
    row = json.loads(result_path.read_text())
    if (row.get('case') != expected['name'] or row.get('source_bytes') != expected['source_bytes']
            or row.get('resource_bytes') != expected['resource_bytes']
            or row.get('occurrences') != expected['occurrences']
            or type(row.get('app_peak_before_bytes')) is not int
            or type(row.get('app_peak_after_bytes')) is not int
            or row['app_peak_after_bytes'] < row['app_peak_before_bytes']):
        raise RuntimeError('App case record differs from the pinned fixture')
    output = case_dir / 'export.html'
    if expected['refusal']:
        if (row.get('outcome') != 'budget-refusal' or row.get('refusal_kind') != expected['refusal_kind']
                or output.exists() or row.get('output_exists') is not False):
            raise RuntimeError('Over-budget refusal published output')
        return {'outcome': 'budget-refusal', 'output_exists': False}
    if row.get('outcome') != 'published' or not output.is_file():
        raise RuntimeError('Expected successful export output is absent')
    size = output.stat().st_size
    if not 0 < size <= (128 << 20) or size != row.get('output_bytes'):
        raise RuntimeError('Output size differs from the app record')
    actual_digest = digest(output)
    if actual_digest != row.get('output_sha256'):
        raise RuntimeError('Output digest differs from the app record')
    inspection = {'outcome': 'published', 'output_bytes': size, 'output_sha256': actual_digest}
    output.unlink()
    return inspection


def measure_case(name, definition, root, app, started_total):
    if app_processes(app):
        raise RuntimeError(name + ' cannot start with a surviving app process')
    case_dir = root / 'cases' / name
    case_dir.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ)
    environment.update({
        'TEST_RUNNER_MOSTLYTEXT_EXPORT_BUDGET_RAMP_CASE': name,
        'TEST_RUNNER_MOSTLYTEXT_EXPORT_BUDGET_RAMP_ROOT': str(root),
        'TEST_RUNNER_MOSTLYTEXT_EXPORT_BUDGET_RAMP_OUTPUT': str(case_dir / 'measurements'),
        'TEST_RUNNER_GITHUB_ACTIONS': 'true',
        'TEST_RUNNER_RUNNER_OS': 'macOS',
        'TEST_RUNNER_GITHUB_REPOSITORY': 'Joncallim/mostlytext',
    })
    baseline_webkit = {pid for pid, _, executable in processes()
                       if Path(executable).name in WEBKIT_HELPERS}
    command = command_for_case(name, root, app)
    samples = []
    started = time.monotonic()
    reason = None
    with (case_dir / 'probe.log').open('w') as log:
        process = subprocess.Popen(command, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                observation = sample(processes(), app, baseline_webkit)
                elapsed = time.monotonic() - started
                samples.append({'elapsed_seconds': round(elapsed, 3), **observation})
                reason = guard_reason(elapsed, time.monotonic() - started_total, observation)
                if reason:
                    terminate_supervisor(process)
                    break
                time.sleep(SAMPLE_SECONDS)
        except BaseException:
            terminate_supervisor(process)
            raise
    memory = {'case': name, 'command_returncode': process.returncode,
              'guard_reason': reason, 'elapsed_seconds': round(time.monotonic() - started, 3),
              'sample_interval_seconds': SAMPLE_SECONDS, 'sample_count': len(samples),
              'baseline_webkit_count': len(baseline_webkit),
              'peak_app_sampled_rss_bytes': max((r['app_rss_bytes'] for r in samples), default=0),
              'peak_new_webkit_sampled_rss_bytes': max((r['new_webkit_rss_bytes'] for r in samples), default=0),
              'cohort_rss_ceiling_bytes': MAX_COHORT_RSS_BYTES, 'case_time_ceiling_seconds': MAX_CASE_SECONDS,
              'scope': 'Exact app RSS plus newly seen same-user WebKit helper cohort; helper attribution unproven'}
    (case_dir / 'memory.json').write_text(json.dumps(memory, indent=2) + '\n')
    (case_dir / 'samples.json').write_text(json.dumps(samples, indent=2) + '\n')
    if reason or process.returncode != 0:
        raise RuntimeError(name + ' stopped: ' + str(reason or process.returncode))
    for _ in range(20):
        if not app_processes(app):
            break
        time.sleep(SAMPLE_SECONDS)
    else:
        raise RuntimeError(name + ' left an app process after test completion')
    inspection = inspect_output(case_dir, {'name': name, **definition})
    (case_dir / 'output-inspection.json').write_text(json.dumps(inspection, indent=2) + '\n')
    measured = json.loads((case_dir / 'measurements' / 'result.json').read_text())
    if measured['app_peak_after_bytes'] >= MAX_COHORT_RSS_BYTES:
        (case_dir / 'post-case-guard.json').write_text(json.dumps({
            'reason': 'app-peak-rss-ceiling', 'app_peak_after_bytes': measured['app_peak_after_bytes'],
            'ceiling_bytes': MAX_COHORT_RSS_BYTES,
        }, indent=2) + '\n')
        raise RuntimeError(name + ' exceeded app peak RSS ceiling between samples')


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: run-export-budget-ramp.py <runner-root> <Release-app-executable>')
    root, app = Path(sys.argv[1]), Path(sys.argv[2])
    check_host(root, app)
    generator = runpy.run_path(str(Path(__file__).with_name('prepare-export-budget-ramp.py')))
    manifest = json.loads((root / 'fixtures' / 'fixture-manifest.json').read_text())
    case_order = tuple(manifest['case_order'])
    if (manifest.get('schema') != 1 or case_order != generator['CASE_ORDER']
            or set(manifest['cases']) != set(case_order)):
        raise RuntimeError('Ramp case order or manifest changed')
    started = time.monotonic()
    for name in case_order:
        if time.monotonic() - started >= MAX_TOTAL_SECONDS:
            (root / 'stop.json').write_text(json.dumps({
                'reason': 'total-time-ceiling', 'next_case': name,
            }, indent=2) + '\n')
            raise RuntimeError('The total ramp time ceiling was reached before ' + name)
        print('Measuring export ramp case ' + name, flush=True)
        measure_case(name, manifest['cases'][name], root, app, started)
    (root / 'run-summary.json').write_text(json.dumps({
        'case_order': list(case_order), 'elapsed_seconds': round(time.monotonic() - started, 3),
        'case_count': len(case_order), 'outcome': 'completed',
    }, indent=2) + '\n')
    print('Completed ' + str(len(case_order)) + ' Release ramp cases', flush=True)


if __name__ == '__main__':
    main()

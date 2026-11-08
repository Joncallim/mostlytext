#!/usr/bin/env python3
"""Sample owned Release app RSS and the newly seen WebKit helper cohort."""
import argparse
import json
import os
from pathlib import Path
import platform
import pwd
import signal
import subprocess
import sys
import time


WEBKIT_HELPERS = {'com.apple.WebKit.WebContent', 'com.apple.WebKit.GPU', 'com.apple.WebKit.Networking'}
MAX_SECONDS = 650
INTERVAL_SECONDS = 0.5


def parse_ps(output, uid):
    rows = []
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) != 4:
            continue
        try:
            pid, owner, rss_kib = map(int, fields[:3])
        except ValueError:
            continue
        if owner == uid and pid > 0 and rss_kib >= 0:
            rows.append({'pid': pid, 'rss_bytes': rss_kib * 1024, 'executable': fields[3]})
    return rows


def current_processes():
    raw = subprocess.check_output(['ps', '-axo', 'pid=,uid=,rss=,comm='], text=True, timeout=10)
    return parse_ps(raw, os.getuid())


def sample(rows, app, baseline_webkit):
    app_bytes = sum(row['rss_bytes'] for row in rows if row['executable'] == str(app))
    webkit = [row for row in rows if Path(row['executable']).name in WEBKIT_HELPERS
              and row['pid'] not in baseline_webkit]
    return {'app_rss_bytes': app_bytes,
            'new_webkit_rss_bytes': sum(row['rss_bytes'] for row in webkit),
            'new_webkit_processes': len(webkit)}


def check_host(output, app, command):
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python cannot qualify a memory sample')
    account = pwd.getpwuid(os.getuid())
    root = Path(os.environ.get('RUNNER_TEMP', '')) / 'export-budget-calibration'
    if (os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.getuid() != os.geteuid() or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or Path.home() != Path('/Users/runner')
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or output != root / 'memory' or not app.is_absolute() or not app.is_file()
            or any(os.path.lexists(p) for p in ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])):
        raise RuntimeError('Refuse non-hosted export calibration or changed output/app identity')
    if (len(command) < 6 or command[:2] != ['python3', '.github/scripts/run-owned-app-tests.py']
            or 'xcodebuild' not in command or 'test-without-building' not in command):
        raise RuntimeError('The bounded owned app-test executor is required')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('app', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    check_host(args.output, args.app, command)
    args.output.mkdir(parents=True, exist_ok=False)
    baseline = {row['pid'] for row in current_processes()
                if Path(row['executable']).name in WEBKIT_HELPERS}
    process = subprocess.Popen(command, start_new_session=True)
    started = time.monotonic()
    cancelled = False
    timed_out = False

    def cancel(_signal, _frame):
        nonlocal cancelled
        cancelled = True

    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    samples = []

    def stop_owned_command():
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()

    try:
        while process.poll() is None:
            elapsed = time.monotonic() - started
            if cancelled or elapsed >= MAX_SECONDS:
                timed_out = not cancelled
                stop_owned_command()
                break
            observation = sample(current_processes(), args.app, baseline)
            samples.append({'elapsed_seconds': round(elapsed, 3), **observation})
            time.sleep(INTERVAL_SECONDS)
    except BaseException:
        stop_owned_command()
        raise
    finally:
        result = {'command_returncode': process.poll(), 'timed_out': timed_out, 'cancelled': cancelled,
                  'elapsed_seconds': round(time.monotonic() - started, 3),
                  'sample_interval_seconds': INTERVAL_SECONDS,
                  'sample_count': len(samples), 'baseline_webkit_count': len(baseline),
                  'peak_app_sampled_rss_bytes': max((row['app_rss_bytes'] for row in samples), default=0),
                  'peak_new_webkit_sampled_rss_bytes': max((row['new_webkit_rss_bytes'] for row in samples), default=0),
                  'scope': 'Sampled app RSS plus newly seen same-user WebKit helper cohort; helper attribution is not proven'}
        (args.output / 'samples.json').write_text(json.dumps(samples, indent=2) + '\n')
        (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    if cancelled:
        raise SystemExit(130)
    if timed_out:
        raise SystemExit(124)
    raise SystemExit(process.returncode if process.returncode >= 0 else 128 - process.returncode)


if __name__ == '__main__':
    main()

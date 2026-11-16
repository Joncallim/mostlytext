#!/usr/bin/env python3
"""Sample the owned Swift test process and newly launched WebKit helpers."""

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


HELPERS = {'com.apple.WebKit.WebContent', 'com.apple.WebKit.GPU', 'com.apple.WebKit.Networking'}
INTERVAL = 0.2
TIMEOUT = 120


def processes():
    raw = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,uid=,rss=,comm='], text=True, timeout=10)
    result = []
    for line in raw.splitlines():
        parts = line.strip().split(None, 4)
        if len(parts) != 5:
            continue
        try:
            pid, parent, uid, kib = map(int, parts[:4])
        except ValueError:
            continue
        if uid == os.getuid() and pid > 0:
            result.append({'pid': pid, 'parent': parent, 'rss_bytes': kib * 1024, 'name': parts[4]})
    return result


def descendants(rows, root):
    selected = {root}
    changed = True
    while changed:
        before = len(selected)
        selected.update(row['pid'] for row in rows if row['parent'] in selected)
        changed = len(selected) != before
    return selected


def check_host(output, command):
    account = pwd.getpwuid(os.getuid())
    expected = Path(os.environ.get('RUNNER_TEMP', '')) / 'diagram-budget-probe' / 'memory'
    if (sys.flags.optimize or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or account.pw_name != 'runner' or account.pw_dir != '/Users/runner'
            or Path.home() != Path('/Users/runner') or os.getuid() != os.geteuid()
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or output.parent != expected or output.exists()
            or any(os.path.lexists(path) for path in ['/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'])
            or command[:2] != ['swift', 'test'] or '--skip-build' not in command
            or '--filter' not in command):
        raise RuntimeError('Refuse non-hosted, unowned or unbounded diagram calibration')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    check_host(args.output, command)
    args.output.mkdir(parents=True)
    before = {row['pid'] for row in processes() if Path(row['name']).name in HELPERS}
    log = args.output / 'test.log'
    started = time.monotonic()
    samples = []
    timed_out = False
    with log.open('w') as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while child.poll() is None:
                if time.monotonic() - started >= TIMEOUT:
                    timed_out = True
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
                    break
                rows = processes()
                owned = descendants(rows, child.pid)
                helpers = [row for row in rows if Path(row['name']).name in HELPERS and row['pid'] not in before]
                samples.append({
                    'elapsed_seconds': round(time.monotonic() - started, 3),
                    'test_group_rss_bytes': sum(row['rss_bytes'] for row in rows if row['pid'] in owned),
                    'new_webkit_rss_bytes': sum(row['rss_bytes'] for row in helpers),
                    'new_webkit_processes': len(helpers),
                })
                time.sleep(INTERVAL)
        except BaseException:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                child.wait(timeout=15)
            raise
    summary = {
        'command': command,
        'returncode': child.returncode,
        'timed_out': timed_out,
        'elapsed_seconds': round(time.monotonic() - started, 3),
        'sample_interval_seconds': INTERVAL,
        'sample_count': len(samples),
        'peak_test_group_rss_bytes': max((row['test_group_rss_bytes'] for row in samples), default=0),
        'peak_new_webkit_rss_bytes': max((row['new_webkit_rss_bytes'] for row in samples), default=0),
        'scope': 'Owned test process descendants plus newly seen same-user WebKit helpers; helper attribution is provisional.',
    }
    (args.output / 'samples.json').write_text(json.dumps(samples, indent=2) + '\n')
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    if child.returncode != 0 or summary['timed_out']:
        raise SystemExit(child.returncode or 1)


if __name__ == '__main__':
    main()

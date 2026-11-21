#!/usr/bin/env python3
"""Temporarily profile one mounted edit after its independent oracle is ready."""

import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import subprocess
import sys
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_host(root):
    account = pwd.getpwuid(os.getuid())
    if (sys.flags.optimize or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/mostlytext'
            or os.environ.get('RUNNER_OS') != 'macOS'
            or account.pw_name != 'runner' or account.pw_dir != '/Users/runner'
            or os.getuid() != os.geteuid() or Path.home() != Path('/Users/runner')
            or platform.machine() != 'arm64' or platform.mac_ver()[0].split('.')[0] != '26'
            or root != Path(os.environ.get('RUNNER_TEMP', '/absent')) / 'viewport-budget'
            or any(os.path.lexists(p) for p in ('/Users/jonathanlim', '/Users/mostlytexttest', '/Volumes/Fast SSD'))):
        raise RuntimeError('refuse non-hosted or owner-account viewport profile')


def await_file(path, process, timeout):
    deadline = time.monotonic() + timeout
    while not path.is_file():
        if process.poll() is not None:
            raise RuntimeError(f'test exited before {path.name}: {process.returncode}')
        if time.monotonic() >= deadline:
            raise TimeoutError(f'test did not create {path.name}')
        time.sleep(0.02)


def await_sample_started(log_path, process):
    deadline = time.monotonic() + 5
    while 'Sampling process' not in log_path.read_text(errors='replace'):
        if process.poll() is not None:
            raise RuntimeError(f'sample exited before capture started: {process.returncode}')
        if time.monotonic() >= deadline:
            raise TimeoutError('sample did not report capture start')
        time.sleep(0.01)
    return time.monotonic_ns()


def main():
    root = Path(os.environ.get('RUNNER_TEMP', '/absent')) / 'viewport-budget'
    require_host(root)
    gate = root / 'profile-gate'
    gate.mkdir(parents=True, exist_ok=False)
    package = Path(os.environ['GITHUB_WORKSPACE']) / 'MacDown2/Packages/MacDownKit'
    env = dict(os.environ, MACDOWN_VIEWPORT_DISPLAY_BENCH='1', MACDOWN_VIEWPORT_PROFILE_GATE=str(gate))
    test_log = root / 'time-aligned-test.log'
    timing = {}
    with test_log.open('wb') as log:
        test = subprocess.Popen(['swift', 'test', '-c', 'release', '--skip-build', '--force-resolved-versions',
                                 '--filter', 'ViewportDisplayBudgetBenchmarkTests', '--no-parallel'],
                                cwd=package, env=env, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True)
        try:
            await_file(gate / 'ready.json', test, 180)
            ready = json.loads((gate / 'ready.json').read_text())
            if ready['case'] != 'begin-word' or ready['source_utf8_bytes'] < 1 << 20:
                raise RuntimeError('wrong mounted source or timed case')
            pid = int(ready['pid'])
            comm = subprocess.check_output(['ps', '-p', str(pid), '-o', 'comm='], text=True).strip()
            if not any(name in comm for name in ('swiftpm-testing-helper', 'MacDownKitPackageTests')):
                raise RuntimeError(f'wrong SwiftPM test host: {comm}')
            timing['ready_monotonic_ns'] = time.monotonic_ns()
            with (root / 'idle-command.log').open('wb') as output:
                subprocess.run(['/usr/bin/sample', str(pid), '1', '1', '-file', str(root / 'idle.sample')],
                               stdout=output, stderr=subprocess.STDOUT, check=True, timeout=20)
            timing['idle_sample_finished_monotonic_ns'] = time.monotonic_ns()
            edit_command_log = root / 'edit-command.log'
            with edit_command_log.open('wb') as output:
                timing['edit_sample_started_monotonic_ns'] = time.monotonic_ns()
                edit_sample = subprocess.Popen(['/usr/bin/sample', str(pid), '1', '1',
                                                '-file', str(root / 'edit.sample')],
                                               stdout=output, stderr=subprocess.STDOUT)
                timing['edit_capture_reported_monotonic_ns'] = await_sample_started(edit_command_log, edit_sample)
                time.sleep(0.10)
                timing['go_monotonic_ns'] = time.monotonic_ns()
                (gate / 'go').touch()
                await_file(gate / 'done', test, 15)
                timing['done_monotonic_ns'] = time.monotonic_ns()
                if edit_sample.wait(timeout=20) != 0:
                    raise RuntimeError('edit sample failed')
                timing['edit_sample_finished_monotonic_ns'] = time.monotonic_ns()
            (gate / 'finish').touch()
            if test.wait(timeout=30) != 0:
                raise RuntimeError(f'mounted benchmark failed: {test.returncode}')
        finally:
            if test.poll() is None:
                test.terminate()
                try:
                    test.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    test.kill()
                    test.wait()
    lines = [line.split(' ', 1)[1] for line in test_log.read_text().splitlines()
             if line.startswith('VIEWPORT-DISPLAY-CASE ')]
    if len(lines) != 1:
        raise RuntimeError(f'expected exactly one timed case, got {len(lines)}')
    case = json.loads(lines[0])
    if case['case'] != 'begin-word' or case['source_utf8_bytes'] < 1 << 20:
        raise RuntimeError('timed case/source identity changed')
    if not (timing['edit_sample_started_monotonic_ns'] <= timing['edit_capture_reported_monotonic_ns']
            < timing['go_monotonic_ns']
            < timing['done_monotonic_ns'] < timing['edit_sample_finished_monotonic_ns']):
        raise RuntimeError('edit did not fit inside its sample interval')
    summary = {'source_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=package,
                                                     text=True).strip(),
               'case': case, 'ready': ready, 'host_comm': comm, 'monotonic_timing_ns': timing,
               'idle_sample_sha256': sha(root / 'idle.sample'),
               'edit_sample_sha256': sha(root / 'edit.sample'),
               'test_log_sha256': sha(test_log),
               'scope': 'single mounted beginning-word edit; sample includes test validation and idle time, but no full-parse oracle construction'}
    (root / 'time-aligned-profile.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, sort_keys=True))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Protected, bounded executor for the first isolated focus test only."""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pwd
import plistlib
import signal
import subprocess
import sys
import tempfile
import time


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected(path):
    require(path.is_absolute() and path == path.resolve(strict=True), 'Protected input is linked')
    require(path.stat().st_uid == 501, 'Protected input must belong to UID 501')
    require(all(not os.access(p, os.W_OK) for p in (path, *path.parents)),
            'Test account can modify a protected input or ancestor')


def verified_pass(exit_code, counts, timed_out):
    expected = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0,
                'skippedTests': 0, 'expectedFailures': 0}
    return type(exit_code) is int and exit_code == 0 and timed_out is False and isinstance(counts, dict) \
        and all(type(counts.get(key)) is int and counts[key] == value for key, value in expected.items())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    options = parser.parse_args()
    require(os.getuid() == os.geteuid() == 502, 'Executor requires test UID 502')
    require(sys.flags.isolated and sys.dont_write_bytecode, 'Use python3 -I -B')
    protected(Path(__file__).absolute())
    root = Path(__file__).resolve().parent.parent
    manifest_path = root / 'binding.json'
    protected(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    for name, expected in manifest['driverSHA256'].items():
        path = root / 'driver' / name
        protected(path)
        require(sha(path) == expected, 'Driver hash differs: ' + name)
    console = os.stat('/dev/console')
    require(console.st_uid == 502, 'Test desktop is not the active console')
    subprocess.run(['/bin/launchctl', 'print', 'gui/502'], check=True, stdout=subprocess.DEVNULL)
    registry = plistlib.loads(subprocess.check_output(['/usr/sbin/ioreg', '-a', '-n', 'Root', '-d', '1']))
    registries = registry if isinstance(registry, list) else [registry]
    require(any(item.get('IOConsoleLocked') is False and any(
        session.get('kCGSSessionUserIDKey') == 502 and session.get('kCGSSessionOnConsoleKey') is True
        and session.get('kCGSessionLoginDoneKey') is True
        for session in item.get('IOConsoleUsers', [])) for item in registries),
        'Active test desktop is unavailable or console is locked')
    control = root / 'native-control.json'
    protected(control)
    proof = json.loads(control.read_text())
    require(proof.get('phase') == 'completed' and proof.get('uid') == 502
            and proof.get('ownerDataDenied') is True, 'Positive control is incomplete')
    spec = importlib.util.spec_from_file_location('fixed_runner', root / 'driver/fixed-issue88-runner-preflight.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    scratch = Path(tempfile.mkdtemp(prefix='MostlyTextFocus-')).resolve()
    args = ['fixed-runner', '--manifest', str(manifest_path), '--owner-home', '/Users/jonathanlim',
            '--scratch', str(scratch), '--build-root', str(root / 'build'),
            '--plan', str(root / 'build/derived/Build/Products/Issue88-isolated-prepared.xctestrun'),
            '--candidate-root', '/Volumes/Fast SSD/CORTANA-Builds/native-completion-20261103/candidate-a75',
            '--expected-patch', str(root / 'build/source.patch')]
    sys.argv = args
    # First run must reach the original hold only after every actual protection,
    # source, signature and process check succeeds. No protection is mocked.
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            runner.main()
    except runner.Refusal as error:
        require(str(error) == 'UI execution remains held pending runtime isolation verification', str(error))
    else:
        raise RuntimeError('Original hold was unexpectedly absent')
    if not options.execute:
        print(json.dumps({'status': 'READY', 'scratch': str(scratch), 'testsRun': 0}))
        return
    # The separately protected executor lifts the in-process hold only now;
    # the repository preflight remains held and cannot execute a command.
    runner.EXECUTION_HOLD = False
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        runner.main()
    prepared = json.loads(output.getvalue())
    command = prepared['command']
    result = Path(command[command.index('-resultBundlePath') + 1])
    require(command == runner.command_for(
        (root / 'build/derived/Build/Products/Issue88-isolated-prepared.xctestrun').resolve(),
        result, manifest['hostID']), 'Executor command changed')
    account = pwd.getpwuid(502)
    env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': account.pw_dir,
           'USER': account.pw_name, 'LOGNAME': account.pw_name,
           'TMPDIR': subprocess.check_output(['/usr/bin/getconf', 'DARWIN_USER_TEMP_DIR'], text=True).strip(),
           'LANG': 'en_US.UTF-8'}
    record = {'status': 'FAIL', 'command': command, 'binding': manifest, 'resultBundle': str(result)}
    start = time.monotonic()
    with (scratch / 'xcodebuild.log').open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            record['timeout'] = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    record.update(exit=process.returncode, elapsed=round(time.monotonic() - start, 2))
    summary = subprocess.run(['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                              '--path', str(result)], capture_output=True, text=True)
    (scratch / 'summary.stdout').write_text(summary.stdout)
    (scratch / 'summary.stderr').write_text(summary.stderr)
    if summary.returncode == 0:
        counts = json.loads(summary.stdout)
        record['summary'] = counts
        if verified_pass(process.returncode, counts, record.get('timeout', False)):
            record['status'] = 'PASS'
    (scratch / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'status': record['status'], 'evidence': str(scratch)}))
    require(record['status'] == 'PASS', 'The selected test did not produce a verified one-case pass')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print('Executor refused or failed: ' + str(error), file=sys.stderr)
        sys.exit(1)

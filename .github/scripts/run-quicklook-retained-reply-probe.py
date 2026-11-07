#!/usr/bin/env python3
"""Bind real QLPreviewReply retention controls to exact owned hosted executables."""
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import subprocess
import sys


SUCCESS = 'QL_RETENTION_PASS holders=8 payloadBytes=8388608 directFactoryCalls=24 exactDrops=8 terminalWinners=1'


def admit():
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python is refused before Quick Look retention preparation')
    expected = {'CI': 'true', 'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
                'RUNNER_OS': 'macOS', 'RUNNER_ARCH': 'ARM64', 'GITHUB_REPOSITORY': 'Joncallim/mostlytext'}
    account = pwd.getpwuid(os.getuid())
    if (any(os.environ.get(k) != v for k, v in expected.items()) or os.getuid() != 501
            or os.getuid() != os.geteuid() or account.pw_name != 'runner' or account.pw_dir != '/Users/runner'
            or Path.home() != Path('/Users/runner') or platform.machine() != 'arm64'
            or Path.cwd() != Path(os.environ.get('GITHUB_WORKSPACE', '/absent')).resolve()
            or Path(os.environ.get('RUNNER_TEMP', '/absent')).resolve() != Path('/Users/runner/work/_temp')):
        raise RuntimeError('Real hosted runner identity required before Quick Look retention preparation')
    if subprocess.check_output(['sw_vers', '-productVersion'], text=True).split('.')[0] != '26':
        raise RuntimeError('Deployment-matching macOS26 is required')


def verify_outcome(log, code, owned, mutant):
    expected = 42 if mutant else 0
    if (code != expected or owned.get('returncode') != expected or owned.get('timed_out') is not False
            or owned.get('cancelled') is not False or owned.get('app_cleanup_requested') != []):
        raise RuntimeError('Native retention execution did not complete with the intended owned result')
    failures = [s for s in log.splitlines() if s.startswith('QL_RETENTION_FAILURE')]
    passes = [s for s in log.splitlines() if s.startswith('QL_RETENTION_PASS')]
    observations = [s for s in log.splitlines() if s.startswith('QL_RETENTION_OBSERVATION')]
    if 'QL_RETENTION_REFUSED' in log or 'QL_RETENTION_UNEXPECTED' in log:
        raise RuntimeError('Native retention execution was refused or failed unexpectedly')
    if mutant:
        if (failures != ['QL_RETENTION_FAILURE retained-before-factory'] or passes
                or observations != ['QL_RETENTION_OBSERVATION live=true holders=0 bytes=0']):
            raise RuntimeError('Counterexample did not isolate premature refund of a live actual reply')
    else:
        expected_observations = ['QL_RETENTION_OBSERVATION live=true holders=' + str(i) +
                                 ' bytes=' + str(i * 1048576) for i in range(1, 9)]
        if failures or passes != [SUCCESS] or observations != expected_observations:
            raise RuntimeError('Original retention controls did not all execute')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def output(command):
    return subprocess.check_output(command, text=True, timeout=60).strip()


def main():
    admit()
    if len(sys.argv) != 1:
        raise RuntimeError('This probe accepts no authority or path override')
    repo = Path.cwd()
    root = Path(os.environ['RUNNER_TEMP']) / 'quicklook-retained-reply'
    root.mkdir(mode=0o700)
    paths = output(['git', 'ls-files', '--', '.github/quicklook-retained-reply-probe',
                    '.github/scripts/run-quicklook-retained-reply-probe.py',
                    '.github/scripts/test-quicklook-retained-reply-probe.py',
                    '.github/scripts/run-owned-app-tests.py', '.github/scripts/test-run-owned-app-tests.py',
                    '.github/workflows/quicklook-retained-reply-probe.yml']).splitlines()
    source = repo / '.github/quicklook-retained-reply-probe/ReplyRetention.swift'
    raw = source.read_bytes()
    needle = b'    return HeldReply(reply: reply, factory: factory, observed: WeakPayload(holder), digest: digest(holder.bytes))'
    if raw.count(needle) != 1:
        raise RuntimeError('The reviewed premature-refund counterexample changed')
    inputs = {p: sha(repo / p) for p in paths}
    if str(source.relative_to(repo)) not in inputs:
        raise RuntimeError('The actual native probe must be a tracked input')
    receipt = {'checkout': output(['git', 'rev-parse', 'HEAD']), 'source_sha256': inputs,
               'root_product_tree': output(['git', 'rev-parse', 'HEAD:MacDown2']),
               'original_cold_finder_fixture_tree': output(['git', 'rev-parse', 'HEAD:.github/quicklook-reply-probe']),
               'swift': output(['xcrun', 'swiftc', '--version']), 'sdk': output(['xcrun', '--show-sdk-version']),
               'phases': [], 'errors': [],
               'scope': 'Actual retained native QLPreviewReply objects and direct calls to the identical factory block; not repeated system calls, Finder cancellation, real rendering or production/final artifact acceptance'}
    if receipt['sdk'].split('.')[0] != '26':
        raise RuntimeError('Require the actual macOS26 SDK')

    def save():
        (root / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def verify_inputs():
        if output(['git', 'rev-parse', 'HEAD']) != receipt['checkout']:
            raise RuntimeError('The actual checkout changed')
        for p, digest in inputs.items():
            if sha(repo / p) != digest:
                raise RuntimeError('An execution input changed: ' + p)
        subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--', 'MacDown2', '.github/quicklook-reply-probe'],
                       check=True, timeout=60, stdout=subprocess.DEVNULL)

    save()
    try:
        for label, contents, mutant in [('original', raw, False),
                                        ('early-refund-mutant', raw.replace(needle, b'    reservation.release()\n' + needle), True),
                                        ('restored', raw, False)]:
            verify_inputs()
            folder = root / label
            folder.mkdir()
            copied = folder / 'ReplyRetention.swift'
            copied.write_bytes(contents)
            binary = folder / 'reply-retention-probe'
            build = ['xcrun', 'swiftc', '-O', '-parse-as-library', '-swift-version', '6',
                     '-strict-concurrency=complete', '-warnings-as-errors', '-target', 'arm64-apple-macos26.0',
                     str(copied), '-o', str(binary)]
            row = {'phase': label, 'source_sha256': sha(copied), 'compile_command': build, 'native_started': False}
            receipt['phases'].append(row)
            save()
            with (folder / 'compile.log').open('x') as log:
                compiled = subprocess.run(build, stdout=log, stderr=subprocess.STDOUT, timeout=120)
            row['compile_returncode'] = compiled.returncode
            save()
            if compiled.returncode:
                raise RuntimeError('First native retention compilation failed: ' + label)
            row['binary_sha256'] = sha(binary)
            command = [sys.executable, str(repo / '.github/scripts/run-owned-app-tests.py'),
                       str(folder / 'diagnostics'), str(binary), '--', str(binary)]
            row.update(command=command, native_started=True)
            save()
            with (folder / 'probe.log').open('x') as log:
                native = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=660)
            owned = json.loads((folder / 'diagnostics/status.json').read_text())
            identity = json.loads((folder / 'diagnostics/identity.json').read_text())
            row.update(supervisor_returncode=native.returncode, actual_owned=owned)
            save()
            if (identity['checkout'] != receipt['checkout'] or identity['app'] != str(binary)
                    or identity['app_sha256'] != row['binary_sha256'] or identity['command'] != [str(binary)]
                    or sha(binary) != row['binary_sha256'] or copied.read_bytes() != contents):
                raise RuntimeError('Actual native retention source/executable/identity changed')
            verify_outcome((folder / 'probe.log').read_text(), native.returncode, owned, mutant)
            verify_inputs()
            row['intended_outcome_verified'] = True
            save()
        receipt['passed'] = True
        save()
    except BaseException as error:
        receipt['errors'].append(repr(error))
        save()
        raise
    print('Actual native original/restored reply-retention controls pass; premature-refund counterexample fails as intended')


if __name__ == '__main__':
    main()

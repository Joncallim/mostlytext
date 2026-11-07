#!/usr/bin/env python3
"""Prove actual snapshot-thread behavior and its counterexample on an owned hosted Mac."""
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import subprocess
import sys


def output(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def admit():
    # Real account lookup prevents an overridden HOME/CI environment admitting the owner account.
    if sys.flags.optimize:
        raise RuntimeError('Optimized Python is refused before file-probe preparation')
    expected = {'CI': 'true', 'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
                'RUNNER_OS': 'macOS', 'RUNNER_ARCH': 'ARM64', 'GITHUB_REPOSITORY': 'Joncallim/mostlytext'}
    account = pwd.getpwuid(os.getuid())
    if (any(os.environ.get(k) != v for k, v in expected.items()) or os.getuid() != 501
            or account.pw_name != 'runner' or account.pw_dir != '/Users/runner'
            or str(Path.home()) != '/Users/runner' or platform.machine() != 'arm64'
            or Path.cwd() != Path(os.environ.get('GITHUB_WORKSPACE', '/absent')).resolve()
            or Path(os.environ.get('RUNNER_TEMP', '/absent')).resolve() != Path('/Users/runner/work/_temp')):
        raise RuntimeError('File-probe execution requires the real owned GitHub-hosted Mac before preparation')
    if output(['sw_vers', '-productVersion']).split('.')[0] != '26':
        raise RuntimeError('Only deployment-matching macOS26 is admitted')


def main():
    admit()
    if len(sys.argv) != 2 or sys.argv[1] not in ['debug', 'release']:
        raise RuntimeError('Select exactly one original configuration')
    configuration = sys.argv[1]
    repo = Path.cwd()
    root = Path(os.environ['RUNNER_TEMP']) / ('file-probe-executor-' + configuration)
    root.mkdir(mode=0o700)
    actual = repo / 'MacDown2/Packages/MacDownKit'
    source = actual / 'Sources/FileCore/DocumentFileProbe.swift'
    test = actual / 'Tests/FileCoreTests/DocumentFileProbeExecutionTests.swift'
    original = source.read_bytes()
    needle = b'return await Task.detached(priority: .utility) {'
    if original.count(needle) != 1:
        raise RuntimeError('The reviewed counterexample location changed')
    mutant = original.replace(needle, b'return await Task(priority: .utility) { @MainActor in')
    paths = output(['git', 'ls-files', 'MacDown2', '.github/scripts/run-file-probe-executor-proof.py',
                    '.github/scripts/run-owned-app-tests.py', '.github/scripts/test-run-owned-app-tests.py',
                    '.github/workflows/file-probe-executor-proof.yml']).splitlines()
    inputs = {p: sha(repo / p) for p in paths}
    lock = actual / 'Package.resolved'
    original_lock = lock.read_bytes()
    pins = json.loads(original_lock)['pins']
    package = root / 'package'
    (package / 'Tests/FileProbeExecutionTests').mkdir(parents=True)
    copied = package / 'Tests/FileProbeExecutionTests/DocumentFileProbeExecutionTests.swift'
    copied.write_bytes(test.read_bytes())
    manifest = ('// swift-tools-version: 6.2\nimport PackageDescription\n'
                'let package = Package(name: "FileProbeExecutor", platforms: [.macOS(.v26)], '
                'dependencies: [.package(path: ' + json.dumps(str(actual)) + ')], '
                'targets: [.testTarget(name: "FileProbeExecutionTests", dependencies: '
                '[.product(name: "FileCore", package: "MacDownKit")])])\n')
    (package / 'Package.swift').write_text(manifest)
    (package / 'Package.resolved').write_text(json.dumps({'version': 2, 'pins': pins}, indent=2) + '\n')
    receipt = {'checkout': output(['git', 'rev-parse', 'HEAD']), 'configuration': configuration,
               'source_sha256': inputs, 'pins': pins, 'focused_lock_format': 2, 'copied_test_sha256': sha(copied),
               'manifest_sha256': sha(package / 'Package.swift'), 'phases': [], 'errors': [],
               'scope': 'Real Foundation-only moved-snapshot thread/hash regression; not UI, timing, idle, storm or final artifact acceptance'}
    record = root / 'receipt.json'

    def save():
        record.write_text(json.dumps(receipt, indent=2) + '\n')

    def verify_inputs(expected_source):
        if source.read_bytes() != expected_source or lock.read_bytes() != original_lock:
            raise RuntimeError('Actual source or canonical pins changed')
        for p, digest in inputs.items():
            expected = hashlib.sha256(expected_source).hexdigest() if repo / p == source else digest
            if sha(repo / p) != expected:
                raise RuntimeError('Unreviewed execution input changed: ' + p)
        if sha(copied) != receipt['copied_test_sha256'] or sha(package / 'Package.swift') != receipt['manifest_sha256']:
            raise RuntimeError('The original copied regression or manifest changed')

    def phase(label, contents, expected):
        source.write_bytes(contents)
        verify_inputs(contents)
        folder = root / label
        folder.mkdir()
        build = ['swift', 'build', '--build-tests', '--package-path', str(package), '--build-path', str(root / 'build'),
                 '--force-resolved-versions', '-c', configuration, '-Xswiftc', '-enable-testing']
        row = {'phase': label, 'source_sha256': sha(source), 'build': build, 'native_started': False}
        receipt['phases'].append(row)
        save()
        with (folder / 'compile.log').open('w') as log:
            built = subprocess.run(build, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        row['build_returncode'] = built.returncode
        save()
        if built.returncode:
            raise RuntimeError(label + ' compilation failed; first result retained')
        binaries = [p for p in (root / 'build').rglob('FileProbeExecutorPackageTests')
                    if p.is_file() and p.parent.name == 'MacOS']
        if len(binaries) != 1:
            raise RuntimeError('Require one actual compiled test executable')
        binary = binaries[0]
        swift = Path(output(['xcrun', '--find', 'swift']))
        helper = swift.parent.parent / 'libexec/swift/pm/swiftpm-testing-helper'
        owned = folder / 'owned-swiftpm-testing-helper'
        shutil.copy2(helper, owned)
        owned.chmod(0o755)
        shutil.copy2(binary, folder / 'compiled-test-executable')
        hashes = {str(p): sha(p) for p in [helper, owned, binary]}
        row['execution_sha256'] = hashes
        command = [sys.executable, str(repo / '.github/scripts/run-owned-app-tests.py'),
                   str(folder / 'diagnostics'), str(owned), '--', str(owned), '--test-bundle-path', str(binary),
                   '--testing-library', 'swift-testing', '--no-parallel', '--filter', 'DocumentFileProbeExecutionTests']
        row.update(command=command, native_started=True)
        save()
        environment = dict(os.environ)
        environment['DYLD_FRAMEWORK_PATH'] = output(['xcrun', '--show-sdk-platform-path']) + '/Developer/Library/Frameworks'
        with (folder / 'probe.log').open('w') as log:
            native = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=environment, timeout=660)
        status = json.loads((folder / 'diagnostics/status.json').read_text())
        row.update(supervisor_returncode=native.returncode, actual_owned=status)
        save()
        verify_inputs(contents)
        if any(sha(Path(p)) != digest for p, digest in hashes.items()):
            raise RuntimeError('An actual native execution input changed')
        if json.loads((package / 'Package.resolved').read_text())['pins'] != pins:
            raise RuntimeError('Focused resolution changed canonical pins')
        log = re.sub(r'\x1b\[[0-9;]*m', '', (folder / 'probe.log').read_text())
        if (native.returncode != expected or status['returncode'] != expected or status['timed_out']
                or status['cancelled'] or status['app_cleanup_requested']):
            raise RuntimeError(label + ' did not finish with its intended owned outcome')
        for size in [1_000_000, 10_000_000]:
            if not re.search('FILE_PROBE_EXECUTION bytes=' + str(size) + r' callbacks=[1-9]\d* mainThread=' +
                             ('true' if expected else 'false'), log):
                raise RuntimeError('Missing actual size/thread observation: ' + str(size))
        outcome = 'failed' if expected else 'passed'
        if not re.search('Test run with 1 test in 1 suite ' + outcome, log) or ' skipped.' in log:
            raise RuntimeError('The exact selected original regression did not completely execute')
        issues = [line for line in log.splitlines() if 'recorded an issue' in line]
        if expected:
            if len(issues) != 2 or any('External snapshot read and digest must run away from the main thread' not in s for s in issues):
                raise RuntimeError('Counterexample failed for another reason')
        elif issues:
            raise RuntimeError('Unchanged source recorded a test issue')
        row['intended_outcome_verified'] = True
        save()

    save()
    try:
        for label, contents, code in [('original', original, 0), ('main-actor-mutant', mutant, 1), ('restored', original, 0)]:
            phase(label, contents, code)
    except BaseException as error:
        receipt['errors'].append(repr(error))
        raise
    finally:
        source.write_bytes(original)
        receipt['original_source_restored'] = source.read_bytes() == original
        save()
    verify_inputs(original)
    receipt['passed'] = True
    save()
    print('Original and restored real snapshot thread controls pass; MainActor counterexample fails as intended')


if __name__ == '__main__':
    main()

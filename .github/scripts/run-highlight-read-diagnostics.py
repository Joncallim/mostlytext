#!/usr/bin/env python3
"""Capture the original Debug parser assertion without modifying the parser."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def output(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if os.environ.get('CI') != 'true':
        parser.error('Native diagnostics execute only in an owned hosted CI environment')
    repo = Path(__file__).resolve().parents[2]
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    actual = repo / 'MacDown2/Packages/MacDownKit'
    names = output(['git', 'ls-files', 'MacDown2', '.github/scripts/run-highlight-read-diagnostics.py',
                    '.github/scripts/record_highlight_read.py', '.github/scripts/run-owned-app-tests.py',
                    '.github/scripts/test-run-owned-app-tests.py', '.github/workflows/highlight-read-diagnostics.yml'],
                   cwd=repo).splitlines()
    sources = {name: digest(repo / name) for name in names}
    lock = actual / 'Package.resolved'
    original_lock = lock.read_bytes()
    pins = json.loads(original_lock)['pins']
    package = destination / 'probe'
    tests = package / 'Tests/HighlightingTests'
    tests.mkdir(parents=True)
    copies = {}
    annotation = b'@Test(.enabled(if: !isDebugBuild))'
    for source in sorted((actual / 'Tests/HighlightingTests').glob('*.swift')):
        raw = source.read_bytes()
        if re.search(rb'Bundle\.module|#filePath|#fileID|#file\b', raw):
            raise SystemExit('Source-relative fixture requires a separate packaging decision: ' + str(source))
        copied = raw
        if source.name == 'NeonReplacementEditTests.swift':
            if raw.count(annotation) != 1:
                raise SystemExit('The original diagnostic experiment gate changed')
            copied = raw.replace(annotation, b'@Test')
        target = package / source.relative_to(actual)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(copied)
        copies[str(source.relative_to(actual))] = {'original_sha256': hashlib.sha256(raw).hexdigest(),
                                                  'executed_sha256': digest(target)}
    if 'Tests/HighlightingTests/NeonReplacementEditTests.swift' not in copies:
        raise SystemExit('The original diagnostic fixture is missing')
    manifest = ('// swift-tools-version: 6.2\nimport PackageDescription\n'
                'let package = Package(name: "HighlightReadDiagnostic", platforms: [.macOS(.v26)], '
                'dependencies: [.package(path: ' + json.dumps(str(actual)) + ')], '
                'targets: [.testTarget(name: "HighlightingTests", dependencies: '
                '[.product(name: "Highlighting", package: "MacDownKit")])])\n')
    (package / 'Package.swift').write_text(manifest)
    (package / 'Package.resolved').write_text(json.dumps({'version': 2, 'pins': pins}) + '\n')
    receipt = {'checkout': output(['git', 'rev-parse', 'HEAD'], cwd=repo), 'source_sha256': sources,
               'pins': pins, 'copied_tests': copies, 'manifest_sha256': digest(package / 'Package.swift'),
               'disposition': 'Diagnostic execution pending; no production fix or issue completion inferred'}
    receipt_path = destination / 'receipt.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    command = ['swift', 'build', '--package-path', str(package), '--scratch-path', str(destination / 'build'),
               '-c', 'debug', '--force-resolved-versions', '-Xswiftc', '-enable-testing']
    with (destination / 'compile.log').open('w') as log:
        subprocess.run(command + ['--build-tests'], check=True, timeout=900,
                       stdout=log, stderr=subprocess.STDOUT)
    binary = (Path(output(command + ['--show-bin-path'])) /
              'HighlightReadDiagnosticPackageTests.xctest/Contents/MacOS/HighlightReadDiagnosticPackageTests')
    developer = Path(output(['xcode-select', '-p']))
    helper = developer / 'Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper'
    owned = destination / 'owned-swiftpm-testing-helper'
    shutil.copyfile(helper, owned)
    owned.chmod(0o700)
    if owned.read_bytes() != helper.read_bytes():
        raise SystemExit('Owned helper copy changed')
    subprocess.run(['codesign', '--force', '--sign', '-', str(owned)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(owned)], check=True)
    dependency_root = destination / 'build/checkouts/SwiftTreeSitter'
    dependency_relative = 'Sources/SwiftTreeSitter/String+Data.swift'
    dependency = dependency_root / dependency_relative
    pinned = [pin for pin in pins if pin['identity'] == 'swifttreesitter']
    if len(pinned) != 1 or output(['git', 'rev-parse', 'HEAD'], cwd=dependency_root) != pinned[0]['state']['revision']:
        raise SystemExit('The assertion dependency is not the committed revision')
    committed = subprocess.check_output(['git', 'show', 'HEAD:' + dependency_relative], cwd=dependency_root)
    if dependency.read_bytes() != committed:
        raise SystemExit('The original dependency assertion source was modified')
    receipt['assertion_dependency'] = {'revision': pinned[0]['state']['revision'], 'path': dependency_relative,
                                       'sha256': digest(dependency)}
    lines = dependency.read_text().splitlines()
    sites = [i + 1 for i, line in enumerate(lines) if 'assertionFailure("location is greater than end")' in line]
    if len(sites) != 1:
        raise SystemExit('The original pinned assertion site changed')
    hashes = {str(path): digest(path) for path in [helper, owned, binary, dependency]}
    commands = destination / 'commands.lldb'
    run_args = [str(owned), '--test-bundle-path', str(binary), '--testing-library', 'swift-testing',
                '--no-parallel', '--filter',
                'widenedBackgroundTypingMatchesAFreshHighlighter|replacementWhileAnInjectedLanguageRequestIsHeldMatchesFreshHighlighting']
    commands.write_text('\n'.join([
        'command script import ' + json.dumps(str(repo / '.github/scripts/record_highlight_read.py')),
        'breakpoint set --file String+Data.swift --line ' + str(sites[0]),
        'breakpoint command add -F record_highlight_read.capture 1',
        'run',
    ]) + '\n')
    environment = dict(os.environ, HIGHLIGHT_READ_DIAGNOSTICS=str(destination),
                       MOSTLYTEXT_HIGHLIGHT_READ_DIAGNOSTIC='1',
                       DYLD_FRAMEWORK_PATH=str(developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'))
    with (destination / 'probe.log').open('w') as log:
        result = subprocess.run([sys.executable, str(repo / '.github/scripts/run-owned-app-tests.py'),
                                 str(destination / 'diagnostics'), str(owned), '--',
                                 'xcrun', 'lldb', '--no-lldbinit', '--batch', '--source', str(commands),
                                 '--one-line-on-crash', 'thread backtrace all', '--'] + run_args,
                                cwd=repo, env=environment, timeout=660, stdout=log, stderr=subprocess.STDOUT)
    receipt['debugger_returncode'] = result.returncode
    receipt['execution_sha256'] = hashes
    receipt['disposition'] = 'Debugger finished; assertion-frame qualification pending'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    status = json.loads((destination / 'diagnostics/status.json').read_text())
    if status['timed_out'] or status['cancelled']:
        raise SystemExit('Debugger execution timed out or was cancelled')
    if any(digest(repo / name) != value for name, value in sources.items()) or lock.read_bytes() != original_lock:
        raise SystemExit('Original source or immutable dependency lock changed')
    if any(digest(Path(name)) != value for name, value in hashes.items()):
        raise SystemExit('Execution product or dependency source changed')
    if any(digest(package / name) != row['executed_sha256'] for name, row in copies.items()):
        raise SystemExit('Diagnostic fixture changed during execution')
    if digest(package / 'Package.swift') != receipt['manifest_sha256']:
        raise SystemExit('Diagnostic package manifest changed')
    if json.loads((package / 'Package.resolved').read_text())['pins'] != pins:
        raise SystemExit('Focused diagnostic dependency pins changed')
    frame_path = destination / 'assertion-frame.json'
    if not frame_path.exists():
        receipt['disposition'] = 'Original assertion not reproduced; triggering values unavailable; no fix established'
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        raise SystemExit(receipt['disposition'])
    observed = json.loads(frame_path.read_text())
    for name in ['byteOffset', 'limit', 'chunkSize', 'location', 'end', 'text_utf16_length']:
        if not isinstance(observed[name], int):
            raise SystemExit('The actual original frame did not yield ' + name)
    if observed['location'] != observed['byteOffset'] // 2 or observed['location'] <= observed['end']:
        raise SystemExit('The original failing read condition was not captured')
    log = (destination / 'probe.log').read_text()
    if not re.search(r'Test (widenedBackgroundTypingMatchesAFreshHighlighter|replacementWhileAnInjectedLanguageRequestIsHeldMatchesFreshHighlighting)\(\) started', log):
        raise SystemExit('Neither selected real editor experiment executed')
    if not re.search(r'String\+Data\.swift:\d+: Fatal error: location is greater than end', log):
        raise SystemExit('The unchanged original assertion did not execute')
    receipt['disposition'] = 'Original assertion values captured; cause and remediation remain unproved'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(receipt['disposition'])


if __name__ == '__main__':
    main()

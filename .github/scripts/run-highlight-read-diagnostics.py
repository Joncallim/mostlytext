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


def replay_passed(code, log, under_debugger=False):
    marker = re.search(r'HIGHLIGHT_READ_CONTROL events=(\[[^\n]*\]) sourceBytes=(\d+)', log)
    if not marker:
        return False
    try:
        events = json.loads(marker[1])
    except json.JSONDecodeError:
        return False
    if not isinstance(events, list):
        return False
    if any(value in log for value in ['Program crashed:', 'stop reason = signal', 'Fatal error:',
                                      'Restarting after unexpected']):
        return False
    normal_exit = not under_debugger or re.search(r'Process \d+ exited with status = 0\b', log)
    return (code == 0 and bool(normal_exit) and 'Test run with 2 tests in 2 suites passed' in log
            and 'recorded an issue at' not in log and events.count('background-held') == 1
            and 'released' in events and 'hold-timed-out' not in events)



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--configuration', choices=['debug', 'release'], default='debug')
    args = parser.parse_args()
    if os.environ.get('CI') != 'true':
        parser.error('Native diagnostics execute only in an owned hosted CI environment')
    repo = Path(__file__).resolve().parents[2]
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    actual = repo / 'MacDown2/Packages/MacDownKit'
    names = output(['git', 'ls-files', 'MacDown2', '.github/scripts/run-highlight-read-diagnostics.py',
                    '.github/scripts/record_highlight_read.py', '.github/scripts/test-highlight-replay-result.py',
                    '.github/scripts/run-owned-app-tests.py',
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
    for source in sorted((actual / 'Tests/HighlightingTests').rglob('*.swift')):
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
               'configuration': args.configuration, 'pins': pins, 'copied_tests': copies, 'manifest_sha256': digest(package / 'Package.swift'),
               'disposition': 'Diagnostic execution pending; no production fix or issue completion inferred'}
    receipt_path = destination / 'receipt.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    command = ['swift', 'build', '--package-path', str(package), '--scratch-path', str(destination / 'build'),
               '-c', args.configuration, '--force-resolved-versions', '-Xswiftc', '-enable-testing']
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
        'process launch --shell-expand-args false',
    ]) + '\n')
    environment = dict(os.environ, HIGHLIGHT_READ_DIAGNOSTICS=str(destination),
                       MOSTLYTEXT_HIGHLIGHT_READ_DIAGNOSTIC='1',
                       DYLD_FRAMEWORK_PATH=str(developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'))
    def execute(label, arguments):
        with (destination / (label + '.log')).open('w') as log:
            result = subprocess.run([sys.executable, str(repo / '.github/scripts/run-owned-app-tests.py'),
                                     str(destination / (label + '-diagnostics')), str(owned), '--'] + arguments,
                                    cwd=repo, env=environment, timeout=660, stdout=log, stderr=subprocess.STDOUT)
        status = json.loads((destination / (label + '-diagnostics/status.json')).read_text())
        if status['timed_out'] or status['cancelled']:
            raise SystemExit('Owned native ' + label + ' timed out or was cancelled')
        return result.returncode, (destination / (label + '.log')).read_text(), status

    direct_code, direct_log, direct_status = execute('direct', run_args)
    debugger = None
    if args.configuration == 'debug':
        debugger = execute('probe', ['xcrun', 'lldb', '--no-lldbinit', '--batch', '--source', str(commands),
                                    '--one-line-on-crash', 'thread backtrace all', '--'] + run_args)
    receipt['direct_status'] = direct_status
    receipt['debugger_status'] = debugger[2] if debugger else None
    receipt['execution_sha256'] = hashes
    receipt['disposition'] = 'Native execution finished; controlled replay and assertion classification pending'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
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
        if not replay_passed(direct_code, direct_log):
            raise SystemExit('Direct controlled replay failed or did not completely execute')
        if debugger and not replay_passed(debugger[0], debugger[1], under_debugger=True):
            raise SystemExit('Debugger controlled replay failed or did not completely execute')
        receipt['controlled_replay_qualified'] = True
        receipt['original_assertion_captured'] = False
        receipt['original_trigger_resolved'] = False
        receipt['disposition'] = ('Strict current controlled replays pass; original assertion not reproduced; '
                                  'triggering values unavailable and original root-cause criterion remains open')
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        print(receipt['disposition'])
        return
    if not debugger or debugger[0] != 0:
        raise SystemExit('Original frame capture requires a successfully launched Debug debugger')
    log = debugger[1]
    observed = json.loads(frame_path.read_text())
    for name in ['byteOffset', 'limit', 'chunkSize', 'location', 'end', 'text_utf16_length']:
        if not isinstance(observed[name], int):
            raise SystemExit('The actual original frame did not yield ' + name)
    if observed['location'] != observed['byteOffset'] // 2 or observed['location'] <= observed['end']:
        raise SystemExit('The original failing read condition was not captured')
    if not re.search(r'Test (widenedBackgroundTypingMatchesAFreshHighlighter|replacementWhileAnInjectedLanguageRequestIsHeldMatchesFreshHighlighting)\(\) started', log):
        raise SystemExit('Neither selected real editor experiment executed')
    if not re.search(r'String\+Data\.swift:\d+: Fatal error: location is greater than end', log):
        raise SystemExit('The unchanged original assertion did not execute')
    receipt['original_assertion_captured'] = True
    receipt['original_trigger_resolved'] = False
    receipt['disposition'] = 'Original assertion values captured; cause and remediation remain unproved'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(receipt['disposition'])


if __name__ == '__main__':
    main()

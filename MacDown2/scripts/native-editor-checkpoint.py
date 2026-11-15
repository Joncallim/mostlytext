#!/usr/bin/env python3
"""Prepare or run the pinned editor checkpoint in the separate test account.

The default plan is read-only. Prepare builds and stages without launching the app.
Accept refuses unless the disposable test desktop is the unlocked console.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid


TESTS = (
    'MacDown2Tests/ExternalSourceFidelityTests',
    'MacDown2Tests/UseDiskVersionRaceTests',
    'MacDown2Tests/ExternalFileWindowOccupancyTests',
    'MacDown2UITests/EditorTypingUITests',
    'MacDown2UITests/ExternalFileChangesUITests',
    'MacDown2UITests/TabLifecycleUITests',
    'MacDown2UITests/DeadKeyCompositionUITests',
)
FIXTURES = (
    'MacDown2/MacDown2Tests/ExternalFileControllerSourceFidelityTests.swift',
    'MacDown2/MacDown2Tests/UseDiskVersionRaceTests.swift',
    'MacDown2/MacDown2UITests/EditorTypingUITests.swift',
    'MacDown2/MacDown2UITests/ExternalFileChangesUITests.swift',
    'MacDown2/MacDown2UITests/TabLifecycleUITests.swift',
    'MacDown2/MacDown2UITests/DeadKeyCompositionUITests.swift',
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(part)
    return result.hexdigest()


def command(args, *, cwd=None, log=None, timeout=1800):
    if log is None:
        return subprocess.run(args, cwd=cwd, check=True, timeout=timeout, capture_output=True, text=True).stdout
    with log.open('w') as output:
        process = subprocess.Popen(args, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise RuntimeError('timed out: ' + ' '.join(args))
    require(code == 0, 'failed (' + str(code) + '): ' + ' '.join(args) + '; log: ' + str(log))


def tree_manifest(root):
    entries = {}
    for path in sorted(root.rglob('*')):
        name = path.relative_to(root).as_posix()
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            require(path.resolve(strict=True).is_relative_to(root), 'product link escapes: ' + name)
            entries[name] = {'type': 'link', 'target': path.readlink().as_posix()}
        elif stat.S_ISREG(mode):
            entries[name] = {'type': 'file', 'sha256': digest(path), 'executable': bool(mode & 0o111)}
        elif stat.S_ISDIR(mode):
            entries[name] = {'type': 'directory'}
        else:
            raise RuntimeError('unsupported product entry: ' + name)
    return entries


def verify_test_plan(path):
    plan = plistlib.loads(path.read_bytes())
    for target in ('MacDown2Tests', 'MacDown2UITests'):
        record = plan.get(target)
        require(isinstance(record, dict), 'missing test target: ' + target)
        require(record.get('TestHostPath', '').startswith('__TESTROOT__/'), 'test host escapes staged products')
        require(record.get('TestBundlePath', '').startswith('__TESTHOST__/'), 'test bundle escapes staged host')
        if target == 'MacDown2UITests':
            require(record.get('UITargetAppPath', '').startswith('__TESTROOT__/'),
                    'UI target escapes staged products')
    require('/Users/jonathanlim' not in str(plan), 'test plan references owner home')


def passed_suites(test_tree, requested):
    counts = {name: 0 for name in requested}

    def visit(node):
        if node.get('nodeType') == 'Test Case':
            require(node.get('result') == 'Passed', 'native test case did not pass')
            url = node.get('nodeIdentifierURL', '')
            for name in requested:
                if url.startswith('test://com.apple.xcode/MacDown2/' + name + '/'):
                    counts[name] += 1
        for child in node.get('children', []):
            visit(child)

    for node in test_tree.get('testNodes', []):
        visit(node)
    require(all(count > 0 for count in counts.values()), 'selected native suite did not execute: ' + str(counts))
    return counts


def source_identity(repo, expected):
    require(repo.is_dir(), 'source checkout missing')
    actual = command(['/usr/bin/git', '-C', str(repo), 'rev-parse', 'HEAD']).strip()
    require(actual == expected and len(actual) == 40, 'source commit differs from pinned SHA')
    require(not command(['/usr/bin/git', '-C', str(repo), 'status', '--porcelain']), 'source checkout is dirty')
    return {name: digest(repo / name) for name in FIXTURES}


def stage_path(sha):
    require(len(sha) == 40 and all(character in '0123456789abcdef' for character in sha), 'invalid SHA')
    return Path('/Applications') / ('MostlyTextEditorCheckpoint-' + sha[:12])


def console_is_test_account():
    require(os.getuid() == os.geteuid() == 502, 'acceptance requires disposable UID 502')
    require(os.stat('/dev/console').st_uid == 502, 'test desktop is not active console')
    command(['/bin/launchctl', 'print', 'gui/502'])
    data = plistlib.loads(subprocess.check_output(['/usr/sbin/ioreg', '-a', '-n', 'Root', '-d', '1']))
    roots = data if isinstance(data, list) else [data]
    require(any(root.get('IOConsoleLocked') is False and any(
        user.get('kCGSSessionUserIDKey') == 502 and user.get('kCGSSessionOnConsoleKey') is True
        and user.get('kCGSessionLoginDoneKey') is True for user in root.get('IOConsoleUsers', []))
        for root in roots), 'test desktop is locked or not on console')
    require(not os.access('/Users/jonathanlim', os.R_OK), 'owner home is readable by test account')


def verify_stage(stage, expected):
    require(stage.is_dir() and not stage.is_symlink(), 'protected stage missing or linked')
    require(stage.stat().st_uid == 501, 'stage is not owned by source owner')
    require(not os.access(stage, os.W_OK), 'stage is writable by test account')
    binding = json.loads((stage / 'binding.json').read_text())
    require(binding['sourceSHA'] == expected, 'stage source differs from pinned SHA')
    require(digest(stage / 'checkpoint.py') == binding['checkpointSHA256'], 'checkpoint entry point changed')
    require(tree_manifest(stage / 'Products') == binding['products'], 'staged test products changed')
    require(digest(stage / 'source-fixtures.json') == binding['fixturesSHA256'], 'fixture manifest changed')
    return binding


def prepare(repo, sha):
    require(os.getuid() == os.geteuid() == 501, 'preparation requires owner UID 501')
    fixtures = source_identity(repo, sha)
    stage = stage_path(sha)
    require(not stage.exists(), 'stage already exists; refuse replacement')
    work = Path(tempfile.mkdtemp(prefix='MostlyTextEditorBuild-'))
    partial = stage.with_name(stage.name + '.partial-' + uuid.uuid4().hex)
    staged = False

    def remove_readonly(function, path, _error):
        Path(path).chmod(Path(path).stat().st_mode | 0o700)
        function(path)

    try:
        command(['python3', 'compliance/tools/compliance.py', 'check'], cwd=repo, log=work / 'compliance.log')
        command(['swiftformat', '--lint', 'MacDown2'], cwd=repo, log=work / 'format.log')
        command(['swiftlint', 'lint', '--strict', '--quiet', 'MacDown2'], cwd=repo, log=work / 'lint.log')
        command(['xcodegen', 'generate'], cwd=repo / 'MacDown2', log=work / 'xcodegen.log')
        command([str(repo / 'MacDown2/scripts/pin-xcode-package-versions.sh')], cwd=repo, log=work / 'pin.log')
        derived = work / 'derived'
        command([
            'xcodebuild', '-project', 'MacDown2/MacDown2.xcodeproj', '-scheme', 'MacDown2',
            '-configuration', 'Release', '-destination', 'platform=macOS', '-derivedDataPath', str(derived),
            '-onlyUsePackageVersionsFromResolvedFile', '-enableCodeCoverage', 'NO',
            'ENABLE_TESTABILITY=YES', 'CODE_SIGNING_ALLOWED=NO',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) RELEASE_PREVIEW_PROBE', 'build-for-testing',
        ], cwd=repo, log=work / 'build.log', timeout=5400)
        command([str(repo / 'MacDown2/scripts/pin-xcode-package-versions.sh'), '--check'], cwd=repo,
                log=work / 'pin-check.log')
        require(source_identity(repo, sha) == fixtures, 'source or fixtures changed during build')
        products = derived / 'Build/Products'
        plans = list(products.glob('*.xctestrun'))
        require(len(plans) == 1, 'expected one pinned Xcode test plan')
        verify_test_plan(plans[0])
        product_entries = tree_manifest(products)
        require(shutil.disk_usage('/Applications').free > sum(
            path.stat().st_size for path in products.rglob('*') if path.is_file() and not path.is_symlink()
        ) * 2, 'insufficient space for protected stage')
        partial.mkdir(mode=0o755)
        shutil.copytree(products, partial / 'Products', symlinks=True)
        shutil.copy2(Path(__file__), partial / 'checkpoint.py')
        (partial / 'source-fixtures.json').write_text(json.dumps(fixtures, indent=2, sort_keys=True) + '\n')
        shutil.copytree(work, partial / 'evidence', ignore=shutil.ignore_patterns('derived'))
        binding = {'sourceSHA': sha, 'xctestrun': plans[0].name, 'tests': TESTS,
                   'products': product_entries, 'fixtureHashes': fixtures,
                   'fixturesSHA256': digest(partial / 'source-fixtures.json'),
                   'checkpointSHA256': digest(partial / 'checkpoint.py'),
                   'signature': 'local unsigned Release test build; not a formal V1 candidate'}
        require(tree_manifest(partial / 'Products') == product_entries, 'copied products differ')
        (partial / 'binding.json').write_text(json.dumps(binding, indent=2, sort_keys=True) + '\n')
        for path in [partial, *partial.rglob('*')]:
            if not path.is_symlink():
                path.chmod(path.stat().st_mode & ~0o222)
        partial.rename(stage)
        staged = True
        print(json.dumps({'status': 'STAGED_NO_LAUNCH', 'sourceSHA': sha, 'stage': str(stage),
                          'fixtureManifestSHA256': binding['fixturesSHA256']}))
    finally:
        if partial.exists():
            shutil.rmtree(partial, onerror=remove_readonly)
        if not staged:
            failure = Path('/Users/Shared') / ('MostlyTextEditorCheckpointFailure-' + sha[:12] + '-' + uuid.uuid4().hex)
            failure.mkdir(mode=0o700)
            for log in work.glob('*.log'):
                shutil.copy2(log, failure / log.name)
            print('PREPARATION_FAILURE_LOGS: ' + str(failure), file=sys.stderr)
        shutil.rmtree(work)


def accept(stage, sha):
    console_is_test_account()
    binding = verify_stage(stage, sha)
    evidence = Path.home() / 'Library/Logs/MostlyTextEditorCheckpoint' / sha / uuid.uuid4().hex
    evidence.mkdir(parents=True, exist_ok=False)
    plan = stage / 'Products' / binding['xctestrun']
    verify_test_plan(plan)
    args = ['xcodebuild', 'test-without-building', '-xctestrun', str(plan),
            '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
            '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '120',
            '-maximum-test-execution-time-allowance', '240', '-resultBundlePath', str(evidence / 'native.xcresult')]
    args.extend('-only-testing:' + item for item in binding['tests'])
    started = time.time()
    result = {'sourceSHA': sha, 'stage': str(stage), 'tests': binding['tests'],
              'fixtureHashes': binding['fixtureHashes'], 'started': started, 'status': 'FAIL'}
    try:
        command(args, log=evidence / 'xcodebuild.log', timeout=3600)
        summary = command(['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                           '--path', str(evidence / 'native.xcresult')])
        (evidence / 'summary.json').write_text(summary)
        tests = command(['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                         '--path', str(evidence / 'native.xcresult')])
        (evidence / 'tests.json').write_text(tests)
        counts = json.loads(summary)
        require(counts.get('failedTests') == 0 and counts.get('skippedTests') == 0
                and counts.get('passedTests', 0) >= len(binding['tests']),
                'native result has failures, skips or missing suite coverage')
        result['passedSuites'] = passed_suites(json.loads(tests), binding['tests'])
        result['status'] = 'AUTOMATED_NATIVE_PASSED_MANUAL_PENDING'
        result['counts'] = counts
    finally:
        result['finished'] = time.time()
        (evidence / 'receipt.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(json.dumps({'status': result['status'], 'evidence': str(evidence)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'prepare', 'accept'))
    parser.add_argument('--sha', required=True, help='exact 40-character source commit')
    parser.add_argument('--source', default=str(Path(__file__).resolve().parents[2]))
    options = parser.parse_args()
    stage = stage_path(options.sha)
    if options.action == 'plan':
        fixtures = source_identity(Path(options.source), options.sha)
        print(json.dumps({'status': 'PLANNED_NO_LAUNCH', 'sourceSHA': options.sha,
                          'stage': str(stage), 'tests': TESTS, 'fixtureHashes': fixtures}, indent=2))
    elif options.action == 'prepare':
        prepare(Path(options.source), options.sha)
    else:
        accept(stage, options.sha)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print('REFUSED: ' + str(error), file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Read-only build preflight. This tool never starts an app or executes a test."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid

EXPECTED_TEST = 'MacDown2UITests/EditingAssistsUITests/testFormattingMenuTracksEditorSidebarFindAndEditorFocus'
BUNDLE_PREFIX = 'com.joncallim.MacDown2.UITestIsolated.'

# Restrict this advisory check to the inspected Xcode-generated plan shape.
# A toolchain change must be reviewed before updating these expectations.
RUNNER_ENV = {
    'APP_DISTRIBUTOR_ID_OVERRIDE':'com.apple.AppStore', 'DYLD_INSERT_LIBRARIES':'/usr/lib/libRPAC.dylib',
    'OS_ACTIVITY_DT_MODE':'YES', 'PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT':'1',
    'PERFC_ENABLE_PROFILE_MODE':'1', 'PERFC_RESET_INSERT_LIBRARIES':'1',
    'PERFC_SUPPRESS_SYSTEM_REPORTS':'1', 'SQLITE_ENABLE_THREAD_ASSERTIONS':'1', 'TERM':'dumb',
}
APP_ENV = {
    'APP_DISTRIBUTOR_ID_OVERRIDE':'com.apple.AppStore',
    'DYLD_FRAMEWORK_PATH':'__TESTROOT__/UITestIsolated:__TESTROOT__/UITestIsolated/PackageFrameworks',
    'DYLD_LIBRARY_PATH':'__TESTROOT__/UITestIsolated', 'XCODE_SCHEME_NAME':'Issue88Isolated',
    '__XCODE_BUILT_PRODUCTS_DIR_PATHS':'__TESTROOT__/UITestIsolated',
    '__XPC_DYLD_FRAMEWORK_PATH':'__TESTROOT__/UITestIsolated',
    '__XPC_DYLD_LIBRARY_PATH':'__TESTROOT__/UITestIsolated',
}
TESTING_ENV = {
    'DYLD_FRAMEWORK_PATH':'__TESTROOT__/UITestIsolated:__TESTROOT__/UITestIsolated/PackageFrameworks:__SHAREDFRAMEWORKS__:__PLATFORMS__/MacOSX.platform/Developer/Library/Frameworks',
    'DYLD_INSERT_LIBRARIES':'__DEVELOPERUSRLIB__/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib',
    'DYLD_LIBRARY_PATH':'__TESTROOT__/UITestIsolated:__PLATFORMS__/MacOSX.platform/Developer/usr/lib',
    'PERFC_SUPPRESS_SYSTEM_REPORTS':'1', 'XCODE_SCHEME_NAME':'Issue88Isolated',
    '__XCODE_BUILT_PRODUCTS_DIR_PATHS':'__TESTROOT__/UITestIsolated',
    '__XPC_DYLD_FRAMEWORK_PATH':'__TESTROOT__/UITestIsolated',
    '__XPC_DYLD_LIBRARY_PATH':'__TESTROOT__/UITestIsolated',
}

class Refusal(Exception):
    pass

def require(condition, message):
    if not condition:
        raise Refusal(message)

def checked_path(path, root):
    path = Path(path)
    root = Path(root).resolve(strict=True)
    actual = path.resolve(strict=True)
    require(actual.is_relative_to(root), 'Product escaped isolated build root')
    return actual

def validate_request(bundle, selected):
    require(selected == [EXPECTED_TEST], 'Exactly the named #88 test must be selected')
    require(bundle.startswith(BUNDLE_PREFIX), 'App identity is not isolated')
    suffix = bundle.removeprefix(BUNDLE_PREFIX)
    try:
        uuid.UUID(suffix)
    except ValueError as e:
        raise Refusal('Invalid app identity UUID') from e
    require(len(suffix) == 36, 'Invalid app identity UUID')

def verify_flags(log, module):
    lines = [line for line in log.splitlines() if 'swiftc ' in line and ('-module-name ' + module + ' ') in line]
    require(any(re.search(r'(?:^|\s)-D\s*DEBUG(?:\s|$)', line) and
                re.search(r'(?:^|\s)-D\s*UITEST_ISOLATED(?:\s|$)', line) for line in lines),
            'Compiled ' + module + ' flags could not be verified')

def validate_plan(original_data, data, bundle, owner_uid):
    require(set(original_data) == {'MacDown2UITests', '__xctestrun_metadata__'}, 'Unexpected plan targets')
    expected_data = copy.deepcopy(original_data)
    expected_target = expected_data.get('MacDown2UITests')
    require(isinstance(expected_target, dict), 'Unexpected generated test target')
    env_copy = expected_target.setdefault('EnvironmentVariables', {})
    require(isinstance(env_copy, dict) and env_copy.get('MOSTLYTEXT_UI_TEST_BUNDLE_ID', bundle) == bundle,
            'Generated runner environment has conflicting identity')
    env_copy['MOSTLYTEXT_UI_TEST_BUNDLE_ID'] = bundle
    env_copy['MOSTLYTEXT_UI_TEST_OWNER_UID'] = str(owner_uid)
    expected_target['TestTimeoutsEnabled'] = True
    expected_target['DefaultTestExecutionTimeAllowance'] = 60
    expected_target['MaximumTestExecutionTimeAllowance'] = 120
    require(data == expected_data, 'Prepared plan differs beyond identity and bounded timeout settings')
    target = data.get('MacDown2UITests')
    require(target.get('CommandLineArguments', []) == [], 'Unexpected runner command-line arguments')
    require(not any(key in target for key in ('OnlyTestIdentifiers', 'SkipTestIdentifiers', 'TestRepetitionMode')),
            'Test plan contains selection or repetition settings')
    return target

def validate_environments(target, bundle, owner_uid):
    expected_runner = dict(RUNNER_ENV, MOSTLYTEXT_UI_TEST_BUNDLE_ID=bundle,
                           MOSTLYTEXT_UI_TEST_OWNER_UID=str(owner_uid))
    require(target.get('EnvironmentVariables') == expected_runner, 'Unexpected runner environment')
    require(target.get('UITargetAppEnvironmentVariables') == APP_ENV, 'Unexpected app environment')
    require(target.get('TestingEnvironmentVariables') == TESTING_ENV, 'Unexpected testing environment')

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def validate_source_manifest(root, receipt):
    manifest_path = root / 'source-manifest.json'
    require(sha(manifest_path) == receipt.get('sourceManifestSHA256'), 'Source manifest differs from build receipt')
    source_files = json.loads(manifest_path.read_text())
    require(isinstance(source_files, dict) and source_files, 'Missing complete source manifest')
    for rel, expected in source_files.items():
        relative = Path(rel)
        require(not relative.is_absolute() and '..' not in relative.parts, 'Invalid source manifest path')
        source = checked_path(root / 'source' / relative, root / 'source')
        require(sha(source) == expected, 'Build source changed: ' + rel)

def inspect_build(args):
    root = args.build_root.resolve(strict=True)
    receipt = json.loads((root / 'receipt.json').read_text())
    require(receipt.get('state') in {'built', 'builds-and-static-preflight-passed'}, 'Build did not complete successfully')
    require(sha(args.expected_patch) == receipt.get('patchSHA256'), 'Patch differs from build receipt')
    validate_source_manifest(root, receipt)
    candidate = args.candidate_root.resolve(strict=True)
    for rel in ('MacDown2/project.yml', 'MacDown2/MacDown2/AppDelegate.swift',
                'MacDown2/MacDown2/UITestLaunchGuard.swift',
                'MacDown2/MacDown2/AppDelegate+UITestLaunch.swift',
                'MacDown2/MacDown2/WindowController+FrameRestore.swift',
                'MacDown2/MacDown2UITests/EditingAssistsUITests.swift'):
        require(sha(root / 'source' / rel) == sha(candidate / rel), 'Build source differs from reviewed candidate: ' + rel)
    bundle = receipt.get('bundleID', '')
    owner_uid = receipt.get('ownerUID')
    require(type(owner_uid) is int and owner_uid > 0, 'Missing protected owner UID')
    validate_request(bundle, args.test)
    build_log = (root / 'build.log').read_text(errors='replace')
    for module in ('MacDown2', 'MacDown2UITests'):
        verify_flags(build_log, module)
    products = checked_path(root / 'derived/Build/Products', root)
    plans = list(products.glob('Issue88Isolated_*.xctestrun'))
    require(len(plans) == 1, 'Expected exactly one generated isolated xctestrun')
    original = checked_path(plans[0], root)
    plan = checked_path(args.plan, root)
    require(plan.parent == products and plan.name == 'Issue88-isolated-prepared.xctestrun',
            'Expected the named disposable plan in the products directory')
    original_data = plistlib.loads(original.read_bytes())
    data = plistlib.loads(plan.read_bytes())
    target = validate_plan(original_data, data, bundle, owner_uid)
    require(isinstance(target, dict) and target.get('IsUITestBundle') is True, 'Unexpected xctestrun test target')
    expected_keys = {
        'BlueprintName', 'BlueprintProviderName', 'BlueprintProviderRelativePath',
        'BundleIdentifiersForCrashReportEmphasis', 'CommandLineArguments', 'DefaultTestExecutionTimeAllowance',
        'MaximumTestExecutionTimeAllowance',
        'DependentProductPaths', 'DiagnosticCollectionPolicy', 'EnvironmentVariables', 'IsUITestBundle',
        'IsXCTRunnerHostedTestBundle', 'PreferredScreenCaptureFormat', 'ProductModuleName', 'RunOrder',
        'SystemAttachmentLifetime', 'TestBundlePath', 'TestHostBundleIdentifier', 'TestHostPath',
        'TestLanguage', 'TestRegion', 'TestTimeoutsEnabled', 'TestingEnvironmentVariables',
        'ToolchainsSettingValue', 'UITargetAppCommandLineArguments', 'UITargetAppEnvironmentVariables',
        'UITargetAppPath', 'UITargetAppPerformanceAntipatternCheckerEnabled', 'UserAttachmentLifetime',
    }
    require(set(target) == expected_keys, 'Unreviewed test-plan target settings')
    expected_values = {
        'BlueprintName': 'MacDown2UITests', 'ProductModuleName': 'MacDown2UITests',
        'TestHostBundleIdentifier': bundle + '.UITests.xctrunner',
        'IsXCTRunnerHostedTestBundle': True, 'RunOrder': 0,
        'TestTimeoutsEnabled': True, 'DefaultTestExecutionTimeAllowance': 60,
        'MaximumTestExecutionTimeAllowance': 120,
        'DependentProductPaths': [
            '__TESTROOT__/UITestIsolated/MacDown2.app',
            '__TESTROOT__/UITestIsolated/MacDown2UITests-Runner.app',
            '__TESTROOT__/UITestIsolated/MacDown2UITests-Runner.app/Contents/PlugIns/MacDown2UITests.xctest',
        ],
    }
    require(all(target.get(key) == value for key, value in expected_values.items()),
            'Unreviewed test-plan values')
    validate_environments(target, bundle, owner_uid)
    require(target.get('UITargetAppCommandLineArguments', []) == [], 'Unexpected app launch arguments in test plan')
    def expand(value):
        require(isinstance(value, str) and value.startswith('__TESTROOT__/'), 'Unexpected product path')
        return checked_path(products / value.removeprefix('__TESTROOT__/'), root)
    app = expand(target.get('UITargetAppPath'))
    runner = expand(target.get('TestHostPath'))
    require(app.name == 'MacDown2.app' and runner.name == 'MacDown2UITests-Runner.app', 'Unexpected product identity')
    require(target.get('TestBundlePath') == '__TESTHOST__/Contents/PlugIns/MacDown2UITests.xctest', 'Unexpected test bundle path')
    test_bundle = checked_path(runner / 'Contents/PlugIns/MacDown2UITests.xctest', root)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == bundle, 'Built app bundle identifier differs from fresh identity')
    require(info.get('MostlyTextUITestOwnerUID') == str(owner_uid), 'App has wrong protected owner identity')
    runner_info = plistlib.loads((runner / 'Contents/Info.plist').read_bytes())
    test_info = plistlib.loads((test_bundle / 'Contents/Info.plist').read_bytes())
    require(runner_info.get('CFBundleIdentifier') == bundle + '.UITests.xctrunner', 'Runner identity is not isolated')
    require(test_info.get('CFBundleIdentifier') == bundle + '.UITests', 'Test bundle identity is not isolated')
    for product in (app, runner, test_bundle):
        p = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(product)], capture_output=True)
        require(p.returncode == 0, 'Code signature verification failed: ' + product.name)
    def executable(bundle_dir, data):
        name = data.get('CFBundleExecutable', '')
        require(name and '/' not in name and name not in ('.', '..'), 'Invalid executable name')
        return checked_path(bundle_dir / 'Contents/MacOS' / name, bundle_dir)
    binaries = {'app': executable(app, info), 'runner': executable(runner, runner_info), 'test': executable(test_bundle, test_info)}
    processes = subprocess.run(['ps', '-axo', 'comm='], text=True, capture_output=True)
    require(processes.returncode == 0, 'Unable to inspect active processes')
    require(not any('MacDown2' in line or 'xctest' in line.lower() for line in processes.stdout.splitlines()),
            'Potential app or test process is active')
    # No implicit environment propagation is assumed. The runner's own
    # EnvironmentVariables must already hold the ID in a disposable plan copy.
    env = target.get('EnvironmentVariables', {})
    require(env.get('MOSTLYTEXT_UI_TEST_BUNDLE_ID') == bundle, 'Runner environment lacks exact app identity')
    require(target.get('UITargetAppEnvironmentVariables', {}).get('MOSTLYTEXT_UI_TEST_BUNDLE_ID', bundle) == bundle,
            'Conflicting app environment identity')
    return {'status':'static-preflight-passed-runtime-isolation-still-unverified',
            'selectedTest':EXPECTED_TEST, 'bundleID':bundle, 'ownerUID':owner_uid,
            'sourceSHA':receipt.get('sourceSHA'), 'sourceManifestSHA256':receipt.get('sourceManifestSHA256'), 'xctestrunSHA256':sha(plan),
            'binarySHA256':{k:sha(v) for k,v in binaries.items()},
            'sourcePatchSHA256':receipt.get('patchSHA256')}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--test', action='append', required=True)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--candidate-root', type=Path, required=True)
    parser.add_argument('--expected-patch', type=Path, required=True)
    print(json.dumps(inspect_build(parser.parse_args()), indent=2))

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException, Refusal) as error:
        print('Preflight refused: ' + str(error), file=sys.stderr)
        sys.exit(1)

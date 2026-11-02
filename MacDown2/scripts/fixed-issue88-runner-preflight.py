#!/usr/bin/env python3
"""Prepare a single fixed #88 command. Execution is deliberately disabled."""
import argparse
import errno
import grp
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import stat
import sys
import uuid
from types import SimpleNamespace

EXPECTED_TEST = 'MacDown2UITests/EditingAssistsUITests/testFormattingMenuTracksEditorSidebarFindAndEditorFocus'
BUNDLE_PREFIX = 'com.joncallim.MacDown2.UITestIsolated.'

class Refusal(Exception):
    pass

def require(condition, message):
    if not condition:
        raise Refusal(message)

def validate_request(bundle, test):
    require(test == EXPECTED_TEST, 'Exactly the named #88 test must be selected')
    require(bundle.startswith(BUNDLE_PREFIX), 'App identity is not isolated')
    suffix = bundle.removeprefix(BUNDLE_PREFIX)
    try:
        uuid.UUID(suffix)
    except ValueError as error:
        raise Refusal('Invalid app identity UUID') from error
    require(len(suffix) == 36, 'Invalid app identity UUID')

def checked_path(path, root):
    actual = Path(path).resolve(strict=True)
    require(actual.is_relative_to(root), 'Product escaped isolated build root')
    return actual

# This hold cannot be overridden by command-line flags or environment variables.
# Runtime, GUI-session and owner-data isolation require separate verification.
EXECUTION_HOLD = True


def validate_manifest(manifest):
    require(manifest.get('version') == 1, 'Unknown binding manifest version')
    require(isinstance(manifest.get('sourceSHA'), str)
            and re.fullmatch(r'[0-9a-f]{40}', manifest['sourceSHA']), 'Invalid source commit in binding manifest')
    validate_request(manifest.get('bundleID', ''), manifest.get('selectedTest'))
    require(re.fullmatch(r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}', manifest.get('hostID', '')) is not None,
                      'Invalid host identity')
    require(isinstance(manifest.get('ownerUID'), int) and manifest['ownerUID'] > 0,
                      'Invalid owner UID')
    require(isinstance(manifest.get('ownerHome'), str) and Path(manifest['ownerHome']).is_absolute(),
                      'Invalid protected owner home')
    for value in [manifest.get('xctestrunSHA256'), manifest.get('sourcePatchSHA256'), manifest.get('sourceManifestSHA256'),
                  *manifest.get('binarySHA256', {}).values()]:
        require(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None,
                          'Invalid digest in binding manifest')
    require(set(manifest.get('binarySHA256', {})) == {'app', 'runner', 'test', 'cli'},
                      'Incomplete executable bindings')


def check_account(manifest):
    uid = os.getuid()
    require(uid == os.geteuid() and uid not in (0, manifest['ownerUID']),
                      'An unprivileged, separate test UID is required')
    account = pwd.getpwuid(uid)
    require(Path.home().resolve() == Path(account.pw_dir).resolve(), 'Login home does not match test UID')
    try:
        admin_gid = grp.getgrnam('admin').gr_gid
    except KeyError as error:
        raise Refusal('Cannot verify administrator-group membership') from error
    require(admin_gid not in set(os.getgroups()) | {account.pw_gid}, 'Test account has administrator membership')


def check_owner_controlled(path, owner_uid):
    require(path.is_absolute() and path == path.resolve(strict=True), 'Binding path must not be a symlink')
    st = path.stat()
    require(st.st_uid == owner_uid and not os.access(path, os.W_OK),
                      'Binding file is not protected from the test account')
    for parent in path.parents:
        require(not os.access(parent, os.W_OK), 'A binding parent is writable by the test account')


def check_products_immutable(paths, root):
    root = root.resolve(strict=True)
    def reject_write(path):
        require(not os.access(path, os.W_OK), 'Test account may modify a product or its container')
    for item in paths:
        requested = Path(os.path.abspath(item))
        require(requested.is_relative_to(root), 'Product must be under the build root')
        for part in (requested, *requested.parents):
            if not part.is_relative_to(root):
                break
            require(not part.is_symlink(), 'Product path has an unreviewed symlink')
        path = checked_path(requested, root)
        # A writable ancestor could replace the complete build root.
        for part in (path, *path.parents):
            reject_write(part)
        if path.is_dir():
            def walk_error(error):
                raise Refusal('Cannot inspect the complete product tree') from error
            for directory, dirs, files in os.walk(path, followlinks=False, onerror=walk_error):
                for name in dirs + files:
                    entry = Path(directory) / name
                    # Reject links until framework link handling is reviewed.
                    require(not entry.is_symlink(), 'Product tree has an unreviewed symlink')
                    reject_write(entry)


def check_private_scratch(path):
    require(path.is_absolute(), 'Scratch path must be absolute')
    require(path == path.resolve(strict=True), 'Scratch path must not be a symlink')
    st = path.stat()
    require(stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid() and st.st_mode & 0o077 == 0,
                      'Scratch directory must be owned by the test UID and owner-only')


def check_denied(paths):
    # Open without reading: ENOENT is not proof of denied access. A successful
    # open is closed and treated as a refusal; no file contents are read.
    for item in paths:
        try:
            fd = os.open(item, os.O_RDONLY | os.O_NOFOLLOW)
        except OSError as error:
            require(error.errno in (errno.EACCES, errno.EPERM), 'Cannot establish access denial')
        else:
            os.close(fd)
            raise Refusal('Test UID can open an owner-protected location')


def command_for(plan, result, host_id):
    require(plan.is_absolute() and result.is_absolute(), 'Plan and result paths must be absolute')
    require(re.fullmatch(r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}', host_id) is not None,
                      'Invalid host identity')
    return ['/usr/bin/xcodebuild', 'test-without-building', '-xctestrun', str(plan),
            '-destination', 'platform=macOS,id=' + host_id,
            '-parallel-testing-enabled', 'NO', '-only-testing:' + EXPECTED_TEST,
            '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '60',
            '-maximum-test-execution-time-allowance', '120', '-test-iterations', '1',
            '-resultBundlePath', str(result)]


def check_binding(manifest, actual):
    for key in ('bundleID', 'ownerUID', 'selectedTest', 'xctestrunSHA256', 'binarySHA256', 'sourcePatchSHA256',
                'sourceSHA', 'sourceManifestSHA256'):
        require(actual.get(key) == manifest.get(key), 'Build binding differs: ' + key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--owner-home', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--candidate-root', type=Path, required=True)
    parser.add_argument('--expected-patch', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    validate_manifest(manifest)
    # This checks only identity, not GUI login, effective ACL behavior in the
    # test runner, or privileged helpers. Those are explicit remaining gates.
    check_account(manifest)
    check_owner_controlled(args.manifest, manifest['ownerUID'])
    check_owner_controlled(Path(__file__).absolute(), manifest['ownerUID'])
    module_path = Path(__file__).absolute().with_name('preflight-issue88-isolation.py')
    check_owner_controlled(module_path, manifest['ownerUID'])
    # Load only after checking the module's location and ownership. The Python
    # interpreter and environment still require a separate trusted setup.
    spec = importlib.util.spec_from_file_location('issue88_preflight', module_path)
    preflight = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preflight)
    owner_home = args.owner_home.resolve(strict=True)
    require(str(owner_home) == manifest['ownerHome'], 'Protected home differs from manifest')
    require(owner_home.stat().st_uid == manifest['ownerUID'], 'Protected home owner mismatch')
    check_denied([owner_home / 'Documents', owner_home / 'Library/Application Support/MacDown 2',
                  owner_home / 'Library/Preferences/com.joncallim.MacDown2.plist'])
    check_private_scratch(args.scratch)
    require(not os.access(args.build_root, os.W_OK), 'Test account may modify build root')
    # Re-run the advisory preflight in this process and bind its exact result.
    values = SimpleNamespace(build_root=args.build_root, plan=args.plan,
                             candidate_root=args.candidate_root, expected_patch=args.expected_patch,
                             test=[EXPECTED_TEST])
    products = args.build_root / 'derived/Build/Products/UITestIsolated'
    check_products_immutable([
        args.plan, products / 'MacDown2.app', products / 'MacDown2UITests-Runner.app', products / 'mostlytext',
    ], args.build_root)
    try:
        checked = preflight.inspect_build(values)
    except preflight.Refusal as error:
        raise Refusal(str(error)) from error
    check_binding(manifest, checked)
    result = args.scratch / ('issue88-' + manifest['bundleID'].removeprefix(BUNDLE_PREFIX) + '.xcresult')
    require(not os.path.lexists(result), 'Result bundle path must be unused')
    command = command_for(args.plan.resolve(strict=True), result, manifest['hostID'])
    # This tool does not call xcodebuild. Even after all static checks, GUI
    # session, immutable products, runtime ownership and result validation are
    # not proven. There is intentionally no flag to override this hold.
    require(not EXECUTION_HOLD, 'UI execution remains held pending runtime isolation verification')
    print(json.dumps({'command': command, 'checks': checked}))

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, Refusal) as error:
        print('Runner preflight refused: ' + str(error), file=sys.stderr)
        sys.exit(1)

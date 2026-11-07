"""Capture exact compiled inputs per phase; no app or native code is executed."""
import hashlib
import json
import os
import platform
import plistlib
import pwd
import subprocess
import sys
from pathlib import Path
import stat

PHASES = {'initial', 'selection'} | {
    kind + '-' + state for kind in ['revision', 'viewport', 'disappear'] for state in ['mutant', 'restored']
}


def read_regular(path):
    path = Path(path)
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > 256 * 1024 * 1024:
        raise RuntimeError('Compiled input is linked, special or exceeds its bound: ' + str(path))
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as handle:
        opened = os.fstat(handle.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_nlink) != (before.st_dev, before.st_ino, 1):
            raise RuntimeError('Compiled input identity changed before read')
        data = handle.read(256 * 1024 * 1024 + 1)
    after = path.lstat()
    if (before.st_dev, before.st_ino, before.st_mtime_ns, before.st_size) != (
            after.st_dev, after.st_ino, after.st_mtime_ns, after.st_size) or len(data) != before.st_size:
        raise RuntimeError('Compiled input changed during read')
    return data


def selected_paths(products, configuration, project):
    products, project = Path(products), Path(project)
    if configuration not in ['Debug', 'Release']:
        raise RuntimeError('Unknown compiled configuration')
    folder = products / configuration
    tests = list(folder.rglob('MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests'))
    runs = list(products.glob('*.xctestrun'))
    if len(tests) != 1 or len(runs) != 1:
        raise RuntimeError('Missing or ambiguous actual test binary/xctestrun')
    expected_test = folder / 'MacDown2.app/Contents/PlugIns/MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests'
    if tests[0] != expected_test:
        raise RuntimeError('Actual test binary is detached from its captured app host')
    candidates = {
        'app_executable': folder / 'MacDown2.app/Contents/MacOS/MacDown2',
        'app_info': folder / 'MacDown2.app/Contents/Info.plist',
        'test_executable': tests[0], 'xctestrun': runs[0],
        'generated_project': project / 'project.pbxproj',
    }
    for role, path in candidates.items():
        parent = project if role == 'generated_project' else products
        if path.resolve() != path or not path.is_relative_to(parent):
            raise RuntimeError('Compiled input path is not a physical descendant: ' + role)
    return candidates


def require_topology(configuration, inputs, blobs):
    try:
        info = plistlib.loads(blobs['app_info'])
        plan = plistlib.loads(blobs['xctestrun'])
    except (ValueError, TypeError) as error:
        raise RuntimeError('Invalid compiled app/run property list') from error
    if not isinstance(info, dict) or info.get('CFBundleIdentifier') != 'app.mostlytext.MostlyText' or info.get('CFBundleExecutable') != 'MacDown2':
        raise RuntimeError('Captured application identity or executable differs')
    target = plan.get('MacDown2Tests') if isinstance(plan, dict) else None
    expected = {'BlueprintName': 'MacDown2Tests', 'ProductModuleName': 'MacDown2Tests',
                'TestHostPath': '__TESTROOT__/' + configuration + '/MacDown2.app',
                'TestHostBundleIdentifier': 'app.mostlytext.MostlyText',
                'TestBundlePath': '__TESTHOST__/Contents/PlugIns/MacDown2Tests.xctest'}
    if (not isinstance(target, dict) or target.get('IsAppHostedTestBundle') is not True
            or any(target.get(key) != value for key, value in expected.items())):
        raise RuntimeError('Actual xctestrun does not select the captured app-hosted tests')
    app = Path(inputs['app_executable']['path']).parents[2]
    if Path(inputs['test_executable']['path']) != app / 'Contents/PlugIns/MacDown2Tests.xctest/Contents/MacOS/MacDown2Tests':
        raise RuntimeError('Captured test executable is not in the selected app host')


def capture(root, products, configuration, project, phase):
    if phase not in PHASES:
        raise RuntimeError('Unknown fixed compiled phase')
    root = Path(root)
    manifest = root / ('compiled-' + phase + '.json')
    if manifest.exists():
        raise RuntimeError('Compiled phase has already been captured')
    paths = selected_paths(products, configuration, project)
    blobs = root / 'compiled-inputs/blobs'
    blobs.mkdir(parents=True, mode=0o700, exist_ok=True)
    rows = {}
    captured = {}
    for role, path in paths.items():
        data = read_regular(path)
        captured[role] = data
        digest = hashlib.sha256(data).hexdigest()
        target = blobs / digest
        if target.exists():
            if read_regular(target) != data:
                raise RuntimeError('Captured compiled blob changed')
        else:
            with target.open('xb') as output:
                output.write(data)
        rows[role] = {'path': str(path), 'sha256': digest, 'bytes': len(data),
                      'blob': str(target.relative_to(root))}
    value = {'phase': phase, 'configuration': configuration, 'inputs': rows}
    require_topology(configuration, rows, captured)
    with manifest.open('x') as output:
        output.write(json.dumps(value, indent=2) + '\n')
    return value


def verify(root, binding):
    root = Path(root)
    if binding.get('phase') not in PHASES or binding.get('configuration') not in ['Debug', 'Release']:
        raise RuntimeError('Retargeted compiled phase')
    manifest = root / ('compiled-' + binding['phase'] + '.json')
    if not manifest.is_file() or json.loads(read_regular(manifest)) != binding:
        raise RuntimeError('Compiled phase differs from its original manifest')
    if set(binding['inputs']) != {'app_executable', 'app_info', 'test_executable', 'xctestrun', 'generated_project'}:
        raise RuntimeError('Incomplete compiled input contract')
    captured = {}
    for role, row in binding['inputs'].items():
        expected = row['sha256']
        if row['blob'] != 'compiled-inputs/blobs/' + expected:
            raise RuntimeError('Compiled archive path cannot be retargeted')
        for path in [Path(row['path']), root / row['blob']]:
            data = read_regular(path)
            if len(data) != row['bytes'] or hashlib.sha256(data).hexdigest() != expected:
                raise RuntimeError('Compiled phase bytes changed: ' + str(path))
        captured[role] = data
    require_topology(binding['configuration'], binding['inputs'], captured)
    return True


def require_owned_phase(identity, binding, checkout):
    app = binding['inputs']['app_executable']
    if identity['app'] != app['path'] or identity['app_sha256'] != app['sha256'] or identity['checkout'] != checkout:
        raise RuntimeError('Actual owned phase used a different app path, bytes or checkout')


def check_host(root):
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python cannot enforce Preview diagnostic admission")
    assert os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_OS") == "macOS"
    assert os.environ.get("GITHUB_REPOSITORY") == "Joncallim/mostlytext"
    account = pwd.getpwuid(os.getuid())
    assert os.getuid() == os.geteuid() > 0 and account.pw_name == "runner" and account.pw_dir == "/Users/runner"
    assert Path.home() == Path("/Users/runner") and platform.machine() == "arm64"
    assert platform.mac_ver()[0].split(".")[0] == "26"
    assert root == Path(os.environ["RUNNER_TEMP"]).resolve() / "preview-grant-probe"
    assert str(root) == "/Users/runner/work/_temp/preview-grant-probe"
    assert not any(os.path.lexists(p) for p in ["/Users/jonathanlim", "/Users/mostlytexttest", "/Volumes/Fast SSD"])
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    if "pull_request" in event:
        assert event["pull_request"]["head"]["repo"]["full_name"] == "Joncallim/mostlytext"
    else:
        assert os.environ["GITHUB_EVENT_NAME"] == "workflow_dispatch"


def verify_execution(root, configuration, phase):
    root = Path(root)
    check_host(root)
    if phase not in PHASES or configuration not in ['Debug', 'Release']:
        raise RuntimeError('Unknown fixed compiled execution phase')
    binding = json.loads((root / ('compiled-' + phase + '.json')).read_text())
    if binding['phase'] != phase or binding['configuration'] != configuration:
        raise RuntimeError('Compiled execution phase was retargeted')
    verify(root, binding)
    owned_folder = ('diagnostics' if phase == 'initial' else 'selection-diagnostics' if phase == 'selection'
                    else 'parsed-frame-' + phase + '-diagnostics')
    identity = json.loads((root / owned_folder / 'identity.json').read_text())
    owned = json.loads((root / owned_folder / 'status.json').read_text())
    receipt = json.loads((root / 'receipt.json').read_text())
    require_owned_phase(identity, binding, receipt['checkout'])
    raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                   '--path', str(root / ('actual-' + phase + '.xcresult'))])
    summary = json.loads(raw)
    (root / ('actual-' + phase + '-summary.json')).write_bytes(raw)
    result = {'phase': phase, 'configuration': configuration, 'compiled_inputs_unchanged_after': True,
              'actual_owned': owned, 'actual_summary': summary,
              'actual_owned_app_matches_captured_executable': True}
    (root / ('compiled-' + phase + '-verified.json')).write_text(json.dumps(result, indent=2) + '\n')
    if owned['timed_out'] or owned['cancelled'] or owned['app_cleanup_requested']:
        raise RuntimeError('Compiled phase has timeout, cancellation or forced-cleanup uncertainty')
    return result

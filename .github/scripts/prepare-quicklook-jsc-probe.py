#!/usr/bin/env python3
"""Prepare/verify only the standalone hosted Quick Look fixture; never launch the product."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import pwd
import re
import plistlib
import shutil
import subprocess
import sys
import uuid

PROVIDER_SUBSYSTEM = 'app.mostlytext.qljscprobe'
CONTROL_SUBSYSTEM = 'app.mostlytext.qljscobserver'
STREAM_COMMAND = ['/usr/bin/log', 'stream', '--style', 'ndjson', '--level', 'info', '--predicate',
                  f'(subsystem == "{PROVIDER_SUBSYSTEM}") OR (subsystem == "{CONTROL_SUBSYSTEM}")']


def parse_live_record(raw):
    if len(raw) > 128 * 1024:
        raise RuntimeError('Actual stream line exceeded128KiB')
    text = raw.decode('utf-8').strip()
    if text.startswith('Filtering the log data using '):
        return None
    try:
        value = json.loads(text)
    except (ValueError, TypeError) as error:
        raise RuntimeError('Malformed actual live log record') from error
    if (not isinstance(value, dict) or value.get('subsystem') not in [PROVIDER_SUBSYSTEM, CONTROL_SUBSYSTEM]
            or not isinstance(value.get('eventMessage'), str)):
        raise RuntimeError('Unknown actual live log namespace/schema')
    return value


def is_control_echo(value, nonce):
    return (value is not None and value['subsystem'] == CONTROL_SUBSYSTEM
            and value['eventMessage'] == 'QL_OBSERVER_CONTROL nonce=' + nonce)


def replay_live_stream(raw, nonce):
    if str(uuid.UUID(nonce)).upper() != nonce or len(raw) > 1024 * 1024 or not raw.endswith(b'\n'):
        raise RuntimeError('Invalid nonce or incomplete/excessive live stream bytes')
    messages = []
    generations = []
    position = 0
    echo = None
    for line in raw.splitlines(keepends=True):
        position += len(line)
        value = parse_live_record(line)
        if is_control_echo(value, nonce) and echo is None:
            echo = position
            generations.append((position, []))
        elif value is not None and value['subsystem'] == PROVIDER_SUBSYSTEM:
            if echo is None:
                raise RuntimeError('Provider event preceded channel admission')
            messages.append(value['eventMessage'])
            generations.append((position, list(messages)))
    if echo is None:
        raise RuntimeError('No actual matching live channel echo')
    return generations


def compile_observer_control(root):
    source = root / 'fixture/ObserverControl.swift'
    binary = root / 'observer-control'
    arguments = ['xcrun', 'swiftc', '-O', '-swift-version', '6', '-strict-concurrency=complete',
                 '-warnings-as-errors', '-target', 'arm64-apple-macos26.0', '-parse-as-library',
                 str(source), '-o', str(binary)]
    record = {'command': arguments, 'source_sha256': digest(source)}
    try:
        result = subprocess.run(arguments, capture_output=True, timeout=60)
        (root / 'observer-control-build.log').write_bytes(result.stdout + result.stderr)
        record['returncode'] = result.returncode
        if binary.exists():
            record['binary_sha256'] = digest(binary)
        if result.returncode:
            raise RuntimeError('Actual hosted channel control compilation failed')
    except BaseException as error:
        record['error'] = repr(error)
        raise
    finally:
        (root / 'observer-control-build.json').write_text(json.dumps(record, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json_attachment(path):
    try:
        value = json.loads(path.read_bytes())
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def validate_provider_entitlements(entitlements):
    assert entitlements == {"com.apple.security.app-sandbox": True,
                            "com.apple.security.files.user-selected.read-only": True}, entitlements


def validate_service_placement(app, provider):
    service = provider / "Contents/XPCServices/QLReplyProbeXPCService.xpc"
    expected = service.relative_to(app)
    if {path.relative_to(app) for path in app.rglob("*.xpc")} != {expected}:
        raise RuntimeError("The placement control requires exactly one extension-level XPC service")
    if service.is_symlink() or not service.is_dir():
        raise RuntimeError("The placement control requires one extension-bundled XPC service")
    return service


def command(args):
    return subprocess.check_output(args, text=True, timeout=60).strip()


def require_standard_python():
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python cannot enforce the Quick Look execution contract")


def validate_trusted_event(event, event_name):
    if "pull_request" in event:
        if event["pull_request"]["head"]["repo"]["full_name"] != "Joncallim/mostlytext":
            raise RuntimeError("Quick Look native execution requires a trusted same-repository head")
    elif event_name != "workflow_dispatch":
        raise RuntimeError("Quick Look native execution requires an explicitly supported event")


WASM_HEX = '0061736d010000000105016000017f03020100070a0106616e7377657200000a06010400412a0b'


def reference_module(root, fixture):
    source = fixture / 'Provider/JavaScriptCapability.swift'
    values = re.findall(r'let wasmHex = "([a-f0-9]+)"', source.read_text())
    if values != [WASM_HEX]: raise RuntimeError('Native module literal differs from independently checked input')
    executable = shutil.which('node')
    if not executable: raise RuntimeError('Require a real independent hosted reference WebAssembly engine')
    executable = str(Path(executable).resolve())
    program = """const crypto=require('node:crypto');const hex=process.argv[1];
const bytes=Uint8Array.from(Buffer.from(hex,'hex'));
if(!WebAssembly.validate(bytes))throw Error('invalid constant module');
const answer=new WebAssembly.Instance(new WebAssembly.Module(bytes),{}).exports.answer();
if(answer!==42)throw Error('wrong constant answer');
process.stdout.write(JSON.stringify({engine:process.version,moduleHex:hex,bytes:bytes.length,
sha256:crypto.createHash('sha256').update(bytes).digest('hex'),answer,valid:true}));"""
    arguments = [executable, '-e', program, WASM_HEX]
    with Path(executable).open('rb') as stream: binary_sha256=hashlib.file_digest(stream,'sha256').hexdigest()
    record={'command':arguments,'source_sha256':digest(source),'binary_sha256':binary_sha256}
    try:
        actual=subprocess.run(arguments,capture_output=True,timeout=15)
        (root/'reference-module.log').write_bytes(actual.stdout+actual.stderr)
        record['returncode']=actual.returncode
        if actual.returncode or actual.stderr: raise RuntimeError('Real reference module validation failed')
        value=json.loads(actual.stdout);record['result']=value
        if (value['moduleHex']!=WASM_HEX or value['answer']!=42 or value['valid'] is not True
                or value['sha256']!=hashlib.sha256(bytes.fromhex(WASM_HEX)).hexdigest()):
            raise RuntimeError('Reference engine did not execute the exact module correctly')
        return record
    except BaseException as error:
        record['error']=repr(error);raise
    finally:
        (root/'reference-module.json').write_text(json.dumps(record,indent=2)+'\n')


def validate_observation(observed, messages):
    if (observed.get('kind')!='mostlytext-qljsc-capability' or type(observed.get('request_id')) is not int
            or observed['request_id']<1 or type(observed.get('baseJS')) is not int or observed['baseJS']!=42
            or observed.get('moduleHex')!=WASM_HEX):
        raise RuntimeError('Require actual basic JavaScript42 and the independently validated module')
    for key in ['started_uptime','observed_uptime']:
        if type(observed.get(key)) not in [float,int] or not math.isfinite(observed[key]) or observed[key]<0:
            raise RuntimeError('Missing actual finite capability timing')
    if observed['observed_uptime']<observed['started_uptime']: raise RuntimeError('Reversed actual capability time')
    for key in ['wasmType','workerType','domType','fetchType','objcType']:
        if observed.get(key) not in ['undefined','object','function','boolean','number','string','symbol','bigint']:
            raise RuntimeError('Unknown actual JavaScript global observation')
    status=observed.get('wasmStatus');answer=observed.get('wasmAnswer')
    errors=[observed.get(k) for k in ['errorPhase','errorName','errorMessage']]
    if status=='available':
        if type(answer) is not int or answer!=42 or observed['wasmType']=='undefined' or errors!=[None,None,None]:
            raise RuntimeError('Available requires actual successful module instantiation/execution42')
    elif status=='unavailable':
        if answer is not None or observed['wasmType']!='undefined' or errors!=[None,None,None]:
            raise RuntimeError('Unavailable requires an actual missing global, not an ignored error')
    elif status=='error':
        if (answer is not None or observed['wasmType']=='undefined' or errors[0] not in ['module','instance','execution']
                or not isinstance(errors[1],str) or not isinstance(errors[2],str) or len(errors[1])>128 or len(errors[2])>512):
            raise RuntimeError('Actual compiler/runtime error needs its precise bounded phase and message')
    else: raise RuntimeError('Unknown capability outcome or wrong actual answer')
    actual=[];factories=[]
    for message in messages:
        if message.startswith('QL_JSC_PROBE result='):
            value=json.loads(message.removeprefix('QL_JSC_PROBE result='))
            if value.get('request_id')==observed['request_id']:actual.append(value)
        match=re.fullmatch(r'QL_JSC_PROBE factory id=(\d+) bytes=(\d+)',message)
        if match and int(match[1])==observed['request_id']:factories.append(int(match[2]))
    if actual!=[observed] or not factories or len(set(factories))!=1 or not 0<factories[0]<=16384:
        raise RuntimeError('Raw provider result/frozen factory does not match the actual UI attachment')


def validate_xpc_observation(observed, messages):
    if (observed.get('kind') != 'mostlytext-qlxpc-capability'
            or set(observed) != {'kind', 'request_id', 'provider_pid', 'service_pid', 'started_uptime'}
            or any(type(observed.get(key)) is not int or observed[key] <= 0
                   for key in ('request_id', 'provider_pid', 'service_pid'))
            or observed['provider_pid'] == observed['service_pid']
            or type(observed.get('started_uptime')) not in (int, float)
            or not math.isfinite(observed['started_uptime']) or observed['started_uptime'] <= 0):
        raise RuntimeError('Invalid actual XPC process observation')
    starts = []
    admissions = []
    service_replies = []
    for message in messages:
        match = re.fullmatch(r'QL_XPC_PROBE begin id=(\d+) provider=(\d+) start=([0-9.]+)', message)
        if match and int(match[1]) == observed['request_id']:
            starts.append((int(match[2]), float(match[3])))
        match = re.fullmatch(r'QL_XPC_PROBE admitted id=(\d+) provider=(\d+) service=(\d+)', message)
        if match and int(match[1]) == observed['request_id']:
            admissions.append((int(match[2]), int(match[3])))
        match = re.fullmatch(r'QL_XPC_SERVICE replied id=(\d+) pid=(\d+) sandbox=1', message)
        if match and int(match[1]) == observed['request_id']:
            service_replies.append(int(match[2]))
    if (starts != [(observed['provider_pid'], observed['started_uptime'])]
            or admissions != [(observed['provider_pid'], observed['service_pid'])]
            or service_replies != [observed['service_pid']]):
        raise RuntimeError('Actual XPC own-request begin/service/admission differs from UI result')


def capture_compiled(root):
    products = root / 'build/Build/Products'
    release = products / 'Release'
    app = release / 'QLReplyProbeContainer.app'
    provider = app / 'Contents/PlugIns/QLReplyProbeProvider.appex'
    service = provider / 'Contents/XPCServices/QLReplyProbeXPCService.xpc'
    runner = release / 'QLReplyProbeFinderTests-Runner.app'
    test = runner / 'Contents/PlugIns/QLReplyProbeFinderTests.xctest'
    plans = list(products.glob('*.xctestrun'))
    if len(plans) != 1:
        raise RuntimeError('Require one actual compiled UI execution plan')
    roles = {'observer_control': root / 'observer-control',
             'app': app / 'Contents/MacOS/QLReplyProbeContainer', 'app_info': app / 'Contents/Info.plist',
             'provider': provider / 'Contents/MacOS/QLReplyProbeProvider', 'provider_info': provider / 'Contents/Info.plist',
             'xpc_service': service / 'Contents/MacOS/QLReplyProbeXPCService',
             'xpc_service_info': service / 'Contents/Info.plist',
             'runner': runner / 'Contents/MacOS/QLReplyProbeFinderTests-Runner', 'runner_info': runner / 'Contents/Info.plist',
             'test': test / 'Contents/MacOS/QLReplyProbeFinderTests', 'test_info': test / 'Contents/Info.plist', 'xctestrun': plans[0],
             'generated_project': root / 'fixture/QuickLookReplyProbe.xcodeproj/project.pbxproj'}
    for base in [app, runner, release / 'QLReplyProbeAutomationHost.app']:
        if not base.is_dir() or not (base / 'Contents/Info.plist').is_file():
            raise RuntimeError('Missing actual signed execution bundle: ' + str(base))
        for path in base.rglob('*'):
            if path.is_file():
                roles['bundle:' + str(path.relative_to(release))] = path
    blobs = root / 'compiled-inputs/blobs'
    blobs.mkdir(parents=True, exist_ok=True)
    captured = {}
    total = 0
    for role, path in roles.items():
        raw = path.read_bytes()
        total += len(raw)
        if len(raw) > 256 * 1024 * 1024 or total > 512 * 1024 * 1024:
            raise RuntimeError('Actual compiled input budget exceeded')
        value = hashlib.sha256(raw).hexdigest()
        destination = blobs / value
        if not destination.exists():
            with destination.open('xb') as stream:
                stream.write(raw)
        if destination.read_bytes() != raw:
            raise RuntimeError('Downloaded compiled input copy differs')
        captured[role] = {'path': str(path), 'bytes': len(raw), 'sha256': value,
                          'blob': str(destination.relative_to(root))}
    return captured


def validate_host_observer(root, checkout):
    driver = json.loads((root / 'host-ui-driver.json').read_text())
    observer = json.loads((root / 'observer-result.json').read_text())
    if (driver['checkout'] != checkout or observer['checkout'] != checkout or driver['errors'] or observer['errors']
            or driver['ui_started'] is not True or driver['ui_supervisor_returncode'] != 0
            or driver['observer_forced_cleanup'] is not False or driver['observer_returncode'] != 0
            or observer['timed_out'] is not False or observer['stopped_after_ui'] is not True
            or driver['observer_pid'] != observer['pid']
            or not driver['ui_completed_monotonic'] <= driver['observer_stop_requested_monotonic']
            <= observer['stop_signal_monotonic'] <= observer['finished_monotonic']
            or not 0 <= observer['admitted_monotonic'] - observer['started_monotonic'] < 5):
        raise RuntimeError('The actual UI and owned host recorder did not complete normally')
    control = root / 'observer-control'
    built = json.loads((root / 'observer-control-build.json').read_text())
    attempts = observer['control_attempts']
    if (observer['mode'] != 'live-ndjson' or observer['stream_command'] != STREAM_COMMAND
            or observer['stream_forced_cleanup'] is not False or observer['stream_returncode'] not in [0, -15]
            or observer['stream_unexpected_exit'] is not False
            or observer['control_sha256'] != digest(control) or built.get('returncode') != 0
            or built['binary_sha256'] != observer['control_sha256'] or 'error' in built
            or not 1 <= len(attempts) <= 25
            or any(x['command'] != [str(control), observer['nonce']] or x['returncode'] != 0 for x in attempts)):
        raise RuntimeError('Actual live channel or compiled control did not qualify')
    raw_stream = (root / 'observer-stream.log').read_bytes()
    if (len(raw_stream) != observer['stream_bytes']
            or hashlib.sha256(raw_stream).hexdigest() != observer['stream_sha256']):
        raise RuntimeError('Actual raw live log bytes changed')
    generations = replay_live_stream(raw_stream, observer['nonce'])
    stderr = (root / 'observer-stream-errors.txt').read_text()
    if any(not line.startswith('Filtering the log data using ') for line in stderr.splitlines()):
        raise RuntimeError('Actual stream stderr contains an unqualified diagnostic')
    rows = observer['snapshots']
    if not 1 <= len(rows) <= 128 or len(rows) != len(generations):
        raise RuntimeError('Incomplete actual host observation history')
    expected = set()
    last = None
    for sequence, row in enumerate(rows):
        name = f'observer-journal/{sequence:03d}.json'
        if row['file'] != name or row['stream_position'] != generations[sequence][0]:
            raise RuntimeError('Unknown/failed host observation generation')
        raw = (root / name).read_bytes()
        if len(raw) != row['bytes'] or len(raw) > 128 * 1024 or hashlib.sha256(raw).hexdigest() != row['sha256']:
            raise RuntimeError('Actual host observation bytes changed')
        value = json.loads(raw)
        if (value['kind'] != 'mostlytext-qljsc-host-observer' or value['checkout'] != checkout
                or value['sequence'] != sequence or not isinstance(value['messages'], list)
                or not all(isinstance(x, str) for x in value['messages'])
                or value['messages'] != generations[sequence][1]):
            raise RuntimeError('Unknown actual host observation schema/source')
        expected.add(f'{sequence:03d}.json')
        last = raw
    if {p.name for p in (root / 'observer-journal').iterdir()} != expected or (root / 'provider-observer.json').read_bytes() != last:
        raise RuntimeError('Current observation does not match its exact immutable history')
    return {'driver': driver, 'observer': observer}


def require_host(root):
    require_standard_python()
    assert os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_OS") == "macOS"
    assert os.environ.get("GITHUB_REPOSITORY") == "Joncallim/mostlytext"
    validate_trusted_event(json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()), os.environ["GITHUB_EVENT_NAME"])
    account = pwd.getpwuid(os.getuid())
    if (os.getuid() != 501 or os.getuid() != os.geteuid() or account.pw_name != 'runner'
            or account.pw_dir != '/Users/runner' or platform.machine() != 'arm64'
            or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'
            or Path.cwd() != Path(os.environ.get('GITHUB_WORKSPACE', '/absent')).resolve()):
        raise RuntimeError('Real hosted runner account and checkout required before preparation')
    assert Path.home() == Path("/Users/runner") and platform.mac_ver()[0].split(".")[0] == "26"
    assert root == Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-qljsc"
    assert Path(os.environ["RUNNER_TEMP"]).resolve() == Path("/Users/runner/work/_temp")


def main():
    require_standard_python()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--verify-built", action="store_true")
    parser.add_argument("--verify-finder", action="store_true")
    parser.add_argument("--seal-built", action="store_true")
    args = parser.parse_args()
    root = args.output.resolve()
    require_host(root)
    receipt_path = root / "receipt.json"
    if not (args.verify_built or args.verify_finder or args.seal_built):
        assert not root.exists()
        root.mkdir(mode=0o700)
        paths = command(["git", "ls-files", "--", ".github/quicklook-jsc-probe",
                         ".github/scripts/prepare-quicklook-jsc-probe.py",
                         ".github/scripts/test-quicklook-jsc-probe.py",
                         ".github/scripts/observe-quicklook-jsc.py",
                         ".github/scripts/run-quicklook-jsc-ui.py",
                         ".github/scripts/test-quicklook-xpc-probe.py",
                         ".github/scripts/capture-quicklook-xpc-launch.py",
                         ".github/scripts/test-quicklook-jsc-observer.py",
                         "planning/downstream/evidence/quicklook-hosted-feasibility-2026-11-07/b000-receipt.json.gz",
                         ".github/scripts/run-owned-app-tests.py", ".github/scripts/test-run-owned-app-tests.py",
                         ".github/workflows/quicklook-jsc-probe.yml"]).splitlines()
        assert paths and any(p.endswith("StaticPreview.swift") for p in paths)
        fixture = root / "fixture"
        shutil.copytree(".github/quicklook-jsc-probe", fixture)
        source = root / "mostlytext-ql-reply-static.md"
        source.write_bytes(b"# Hosted Quick Look fixture\n")
        (root / "mostlytext-ql-jsc.md").write_bytes(b"# Hosted Quick Look fixture\n")
        (root / "mostlytext-ql-xpc.md").write_bytes(b"# Hosted Quick Look fixture\n")
        (root / "ql-probe-neighbor.md").write_bytes(b"Generated sibling capability control; do not read through the provider.\n")
        record = {"checkout": command(["git", "rev-parse", "HEAD"]),
                  "source_sha256": {p: digest(Path(p)) for p in paths},
                  "fixture_source_sha256": {str(p.relative_to(fixture)): digest(p) for p in fixture.rglob("*") if p.is_file()},
                  "selected_fixture_sha256": digest(source),
                  "root_product_tree": command(["git", "rev-parse", "HEAD:MacDown2"]),
                  "xcode": command(["xcodebuild", "-version"]), "os": command(["sw_vers"]),
                  "diagnostic_only": True, "qualification_candidate": False,
                  "scope": "Separate disposable hosted JavaScriptCore and XPC reachability observation; no root product launch, shipping extension, full QL-REPLY or owner acceptance"}
        receipt_path.write_text(json.dumps(record, indent=2) + "\n")
        record['reference_module']=reference_module(root,fixture)
        subprocess.run(["xcodegen", "generate", "--spec", str(fixture / "project.yml")], check=True, timeout=60)
        record["generated_sha256"] = {str(p.relative_to(fixture)): digest(p) for p in fixture.rglob("*") if p.is_file()}
        receipt_path.write_text(json.dumps(record, indent=2) + "\n")
        return
    record = json.loads(receipt_path.read_text())
    if record.get('diagnostic_only') is not True or record.get('qualification_candidate') is not False:
        raise RuntimeError('Capability observation cannot become a renderer qualification')
    reference=record['reference_module']
    with Path(reference['command'][0]).open('rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!=reference['binary_sha256']:
            raise RuntimeError('Independent reference engine bytes changed')
    if reference['result']['moduleHex']!=WASM_HEX or reference['result']['answer']!=42:
        raise RuntimeError('Original independent module validation changed')
    assert record["checkout"] == command(["git", "rev-parse", "HEAD"])
    for name, expected in record["source_sha256"].items():
        assert digest(Path(name)) == expected, name
    fixture = root / "fixture"
    for name, expected in record["generated_sha256"].items():
        assert digest(fixture / name) == expected, name
    app = root / "build/Build/Products/Release/QLReplyProbeContainer.app"
    provider = app / "Contents/PlugIns/QLReplyProbeProvider.appex"
    service = validate_service_placement(app, provider)
    app_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    info = plistlib.loads((provider / "Contents/Info.plist").read_bytes())
    service_info = plistlib.loads((service / "Contents/Info.plist").read_bytes())
    assert app_info["CFBundleIdentifier"] == "app.mostlytext.MostlyText"
    assert not app_info.get("CFBundleDocumentTypes"), "The fixture must not claim a default document handler"
    assert info["CFBundleIdentifier"] == "app.mostlytext.MostlyText.QuickLook"
    assert service_info["CFBundleIdentifier"] == "app.mostlytext.QLReplyProbe.XPCService"
    assert service_info["XPCService"]["ServiceType"] == "Application"
    ext = info["NSExtension"]
    assert ext["NSExtensionPointIdentifier"] == "com.apple.quicklook.preview"
    assert ext["NSExtensionPrincipalClass"] == "QLReplyProbeProvider.StaticPreview"
    assert ext["NSExtensionAttributes"] == {"QLIsDataBasedPreview": True, "QLSupportedContentTypes": ["net.daringfireball.markdown"]}
    if args.seal_built:
        # UI-test instrumentation belongs only to the separate automation target.
        subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime", "--timestamp=none",
                        "--entitlements", str(fixture / "Provider.entitlements"), str(provider)], check=True, timeout=30)
        subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime", "--timestamp=none",
                        str(app)], check=True, timeout=30)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, timeout=30)
    result = subprocess.run(["codesign", "--display", "--entitlements", "-", "--xml", str(provider)],
                            capture_output=True, check=True, timeout=30)
    raw = result.stdout
    if b"<?xml" not in raw:
        raw = result.stderr[result.stderr.index(b"<?xml"):]
    entitlements = plistlib.loads(raw[raw.index(b"<?xml"):])
    validate_provider_entitlements(entitlements)
    (root / "provider-actual-entitlements.plist").write_bytes(plistlib.dumps(entitlements))
    result = subprocess.run(["codesign", "--display", "--entitlements", "-", "--xml", str(service)],
                            capture_output=True, check=True, timeout=30)
    (root / "xpc-service-codesign-stdout.txt").write_bytes(result.stdout)
    (root / "xpc-service-codesign-stderr.txt").write_bytes(result.stderr)
    raw = result.stdout
    if b"<?xml" not in raw:
        raw = result.stderr[result.stderr.index(b"<?xml"):]
    service_entitlements = plistlib.loads(raw[raw.index(b"<?xml"):])
    (root / "xpc-service-observed-entitlements.plist").write_bytes(plistlib.dumps(service_entitlements))
    if service_entitlements != {"com.apple.security.app-sandbox": True}:
        raise RuntimeError("XPC service has unexpected entitlement or missing sandbox")
    (root / "xpc-service-actual-entitlements.plist").write_bytes(plistlib.dumps(service_entitlements))
    record["built"] = {"app_info": app_info, "provider_info": info, "entitlements": entitlements,
                       "service_info": service_info, "service_entitlements": service_entitlements,
                       "app_executable_sha256": digest(app / "Contents/MacOS" / app_info["CFBundleExecutable"]),
                       "provider_executable_sha256": digest(provider / "Contents/MacOS" / info["CFBundleExecutable"]),
                       "service_executable_sha256": digest(service / "Contents/MacOS" / service_info["CFBundleExecutable"])}
    if args.seal_built:
        assert "built_before_test" not in record
        compile_observer_control(root)
        record["built_before_test"] = record["built"]
        record['compiled_before_test'] = capture_compiled(root)
    else:
        assert record["built"] == record["built_before_test"], "Test setup changed actual provider/container identity or permissions"
        if capture_compiled(root) != record['compiled_before_test']:
            raise RuntimeError('An actual compiled UI/provider execution input changed')
    assert digest(root / "mostlytext-ql-reply-static.md") == record["selected_fixture_sha256"]
    assert digest(root / "mostlytext-ql-jsc.md") == record["selected_fixture_sha256"]
    assert digest(root / "mostlytext-ql-xpc.md") == record["selected_fixture_sha256"]
    if args.verify_finder:
        record['host_observer_proof'] = validate_host_observer(root, record['checkout'])
        controls = json.loads((root / 'observer-control-events.json').read_text())
        nonce = record['host_observer_proof']['observer']['nonce']
        if not isinstance(controls, list) or not any(isinstance(x, dict) and is_control_echo(x, nonce) for x in controls):
            raise RuntimeError('Independent actual host log lacks the emitted startup nonce')
        record['observer_control_log_sha256'] = digest(root / 'observer-control-events.json')
        events = json.loads((root / "provider-events.json").read_text())
        messages = [x.get("eventMessage", "") for x in events if isinstance(x, dict)]
        assert not any("container-launched-invalidates-cold-proof" in x for x in messages), "Containing fixture actually launched"
        for marker in ["QL_REPLY_PROBE self-entitlement-policy-admitted", "QL_REPLY_PROBE callback", "QL_REPLY_PROBE selected-read", "QL_REPLY_PROBE sibling-open-admitted", "QL_REPLY_PROBE replied", "QL_REPLY_PROBE factory"]:
            assert any(marker in x for x in messages), marker
        owned = json.loads((root / "owned/status.json").read_text())
        identity = json.loads((root / "owned/identity.json").read_text())
        assert owned["returncode"] == 0 and not owned["timed_out"] and not owned["cancelled"]
        assert identity["checkout"] == record["checkout"]
        assert identity["app_sha256"] == record["built"]["provider_executable_sha256"]
        record["cold_finder_test"] = {"owned_status": owned, "actual_provider_events": [x for x in messages if "QL_REPLY_PROBE" in x],
                                      "event_log_sha256": digest(root / "provider-events.json"),
                                      "scope": "Actual visible Finder marker and static provider callback/factory only; image presentation still needs screenshot inspection; not full QL-REPLY"}
        if owned['app_cleanup_requested']:
            raise RuntimeError('Forced native cleanup cannot qualify a pending Finder observation')
        result = root / 'Finder.xcresult'
        raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], timeout=60)
        (root / 'actual-ui-summary.json').write_bytes(raw)
        summary = json.loads(raw)
        expected = {'totalTestCount': 3, 'passedTests': 3, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
        if any(type(summary.get(k)) is not int or summary[k] != v for k, v in expected.items()):
            raise RuntimeError('Both original Finder cases and actual XPC reachability must pass')
        attachments = root / 'actual-ui-attachments'
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(attachments)], check=True, timeout=60)
        observations = []
        for path in attachments.rglob('*'):
            if path.is_file() and path.stat().st_size <= 128 * 1024:
                try:
                    value = json.loads(path.read_bytes())
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                if isinstance(value, dict) and value.get('kind') == 'mostlytext-qljsc-capability':
                    observations.append(value)
        if len(observations) != 1:
            raise RuntimeError('Require one actual result-bundle pending Finder attachment')
        validate_observation(observations[0], messages)
        xpc = [value for path in attachments.rglob('*') if path.is_file() and path.stat().st_size <= 128 * 1024
               for value in [load_json_attachment(path)] if value and value.get('kind') == 'mostlytext-qlxpc-capability']
        if len(xpc) != 1:
            raise RuntimeError('Require one actual XPC process result attachment')
        validate_xpc_observation(xpc[0], messages)
        record['javascriptcore_capability_observation'] = observations[0]
        record['xpc_reachability_observation'] = xpc[0]
        record['actual_ui_summary'] = summary
        record['scope'] = 'Actual fixed JavaScriptCore and XPC service reachability only; no engine deadline/fallback, new authority, production or full QL-REPLY acceptance'
    receipt_path.write_text(json.dumps(record, indent=2) + "\n")
    print("Actual signed fixture identifiers, Markdown-only data provider, sandbox entitlements and source hashes verified")


if __name__ == "__main__":
    main()

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


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_provider_entitlements(entitlements):
    assert entitlements == {"com.apple.security.app-sandbox": True,
                            "com.apple.security.files.user-selected.read-only": True}, entitlements


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


def validate_observation(observed, messages):
    if observed.get('kind') != 'mostlytext-qlcancel-observation' or observed.get('selected') != 'mostlytext-ql-reply-cancel.md':
        raise RuntimeError('Require the actual generated cancellation-file observation')
    request = observed.get('request_id')
    if type(request) is not int or request < 1:
        raise RuntimeError('Require one actual provider request identity')
    times = [observed.get(k) for k in ['provider_started', 'observed_pending', 'escape_sent', 'window_closed', 'provider_terminal']]
    if any(type(x) not in [int, float] or not math.isfinite(x) for x in times):
        raise RuntimeError('Missing actual monotonic observations')
    start, pending, escape, closed, terminal = times
    if not (start < pending < escape <= closed and escape <= terminal):
        raise RuntimeError('Finder was not observed closing a genuinely pending request')
    entries = []
    for message in messages:
        match = re.fullmatch(r'QL_CANCEL_PROBE (pending|handler|terminal-cancelled|terminal-completed) id=(\d+) uptime=([\d.]+)', message)
        if match and int(match[2]) == request:
            entries.append((match[1], float(match[3])))
    starts = [t for phase, t in entries if phase == 'pending']
    terminals = [(phase, t) for phase, t in entries if phase.startswith('terminal-')]
    handlers = [t for phase, t in entries if phase == 'handler']
    if starts != [start] or terminals != [(observed.get('terminal_kind'), terminal)]:
        raise RuntimeError('Actual provider log and UI attachment do not identify one complete request')
    cancelled = observed.get('system_task_cancellation_observed')
    if observed['terminal_kind'] == 'terminal-cancelled':
        if cancelled is not True or len(handlers) != 1 or not escape <= handlers[0] <= terminal:
            raise RuntimeError('Missing actual post-Escape system-task cancellation')
    elif observed['terminal_kind'] == 'terminal-completed':
        if cancelled is not False or handlers or not closed < terminal:
            raise RuntimeError('Wait completion must genuinely occur after Finder closure without task cancellation')
    else:
        raise RuntimeError('Unknown actual provider terminal outcome')


def capture_compiled(root):
    products = root / 'build/Build/Products'
    release = products / 'Release'
    app = release / 'QLReplyProbeContainer.app'
    provider = app / 'Contents/PlugIns/QLReplyProbeProvider.appex'
    runner = release / 'QLReplyProbeFinderTests-Runner.app'
    test = runner / 'Contents/PlugIns/QLReplyProbeFinderTests.xctest'
    plans = list(products.glob('*.xctestrun'))
    if len(plans) != 1:
        raise RuntimeError('Require one actual compiled UI execution plan')
    roles = {'app': app / 'Contents/MacOS/QLReplyProbeContainer', 'app_info': app / 'Contents/Info.plist',
             'provider': provider / 'Contents/MacOS/QLReplyProbeProvider', 'provider_info': provider / 'Contents/Info.plist',
             'runner': runner / 'Contents/MacOS/QLReplyProbeFinderTests-Runner', 'runner_info': runner / 'Contents/Info.plist',
             'test': test / 'Contents/MacOS/QLReplyProbeFinderTests', 'test_info': test / 'Contents/Info.plist', 'xctestrun': plans[0],
             'generated_project': root / 'fixture/QuickLookReplyProbe.xcodeproj/project.pbxproj'}
    for base in [app, runner]:
        for path in base.rglob('*.dylib'):
            roles['dylib:' + str(path.relative_to(release))] = path
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


def main():
    require_standard_python()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--verify-built", action="store_true")
    parser.add_argument("--verify-finder", action="store_true")
    parser.add_argument("--seal-built", action="store_true")
    args = parser.parse_args()
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
    root = args.output.resolve()
    assert root == Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-qlcancel"
    receipt_path = root / "receipt.json"
    if not (args.verify_built or args.verify_finder or args.seal_built):
        assert not root.exists()
        root.mkdir(mode=0o700)
        paths = command(["git", "ls-files", "--", ".github/quicklook-cancellation-probe",
                         ".github/scripts/prepare-quicklook-cancellation-probe.py",
                         ".github/scripts/test-quicklook-cancellation-probe.py",
                         "planning/downstream/evidence/quicklook-hosted-feasibility-2026-11-07/b000-receipt.json.gz",
                         ".github/scripts/run-owned-app-tests.py", ".github/scripts/test-run-owned-app-tests.py",
                         ".github/workflows/quicklook-cancellation-probe.yml"]).splitlines()
        assert paths and any(p.endswith("StaticPreview.swift") for p in paths)
        fixture = root / "fixture"
        shutil.copytree(".github/quicklook-cancellation-probe", fixture)
        source = root / "mostlytext-ql-reply-static.md"
        source.write_bytes(b"# Hosted Quick Look fixture\n")
        (root / "mostlytext-ql-reply-cancel.md").write_bytes(b"# Hosted Quick Look fixture\n")
        (root / "ql-probe-neighbor.md").write_bytes(b"Generated sibling capability control; do not read through the provider.\n")
        record = {"checkout": command(["git", "rev-parse", "HEAD"]),
                  "source_sha256": {p: digest(Path(p)) for p in paths},
                  "fixture_source_sha256": {str(p.relative_to(fixture)): digest(p) for p in fixture.rglob("*") if p.is_file()},
                  "selected_fixture_sha256": digest(source),
                  "root_product_tree": command(["git", "rev-parse", "HEAD:MacDown2"]),
                  "xcode": command(["xcodebuild", "-version"]), "os": command(["sw_vers"]),
                  "scope": "Separate disposable hosted Finder cancellation observation; no root product launch, shipping extension, full QL-REPLY or owner acceptance"}
        subprocess.run(["xcodegen", "generate", "--spec", str(fixture / "project.yml")], check=True, timeout=60)
        record["generated_sha256"] = {str(p.relative_to(fixture)): digest(p) for p in fixture.rglob("*") if p.is_file()}
        receipt_path.write_text(json.dumps(record, indent=2) + "\n")
        return
    record = json.loads(receipt_path.read_text())
    assert record["checkout"] == command(["git", "rev-parse", "HEAD"])
    for name, expected in record["source_sha256"].items():
        assert digest(Path(name)) == expected, name
    fixture = root / "fixture"
    for name, expected in record["generated_sha256"].items():
        assert digest(fixture / name) == expected, name
    app = root / "build/Build/Products/Release/QLReplyProbeContainer.app"
    provider = app / "Contents/PlugIns/QLReplyProbeProvider.appex"
    app_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    info = plistlib.loads((provider / "Contents/Info.plist").read_bytes())
    assert app_info["CFBundleIdentifier"] == "app.mostlytext.MostlyText"
    assert not app_info.get("CFBundleDocumentTypes"), "The fixture must not claim a default document handler"
    assert info["CFBundleIdentifier"] == "app.mostlytext.MostlyText.QuickLook"
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
    record["built"] = {"app_info": app_info, "provider_info": info, "entitlements": entitlements,
                       "app_executable_sha256": digest(app / "Contents/MacOS" / app_info["CFBundleExecutable"]),
                       "provider_executable_sha256": digest(provider / "Contents/MacOS" / info["CFBundleExecutable"])}
    if args.seal_built:
        assert "built_before_test" not in record
        record["built_before_test"] = record["built"]
        record['compiled_before_test'] = capture_compiled(root)
    else:
        assert record["built"] == record["built_before_test"], "Test setup changed actual provider/container identity or permissions"
        if capture_compiled(root) != record['compiled_before_test']:
            raise RuntimeError('An actual compiled UI/provider execution input changed')
    assert digest(root / "mostlytext-ql-reply-static.md") == record["selected_fixture_sha256"]
    assert digest(root / "mostlytext-ql-reply-cancel.md") == record["selected_fixture_sha256"]
    if args.verify_finder:
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
        expected = {'totalTestCount': 2, 'passedTests': 2, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
        if any(type(summary.get(k)) is not int or summary[k] != v for k, v in expected.items()):
            raise RuntimeError('Both real original cold-Finder and pending-closure cases must pass')
        attachments = root / 'actual-ui-attachments'
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(attachments)], check=True, timeout=60)
        observations = []
        for path in attachments.rglob('*'):
            if path.is_file() and path.stat().st_size <= 128 * 1024:
                try:
                    value = json.loads(path.read_bytes())
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                if isinstance(value, dict) and value.get('kind') == 'mostlytext-qlcancel-observation':
                    observations.append(value)
        if len(observations) != 1:
            raise RuntimeError('Require one actual result-bundle pending Finder attachment')
        validate_observation(observations[0], messages)
        record['pending_finder_observation'] = observations[0]
        record['actual_ui_summary'] = summary
        record['scope'] = 'Actual pending Finder closure and observed system task cancellation behavior only; no production cancellation, real-renderer fallback or full QL-REPLY claim'
    receipt_path.write_text(json.dumps(record, indent=2) + "\n")
    print("Actual signed fixture identifiers, Markdown-only data provider, sandbox entitlements and source hashes verified")


if __name__ == "__main__":
    main()

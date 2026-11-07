#!/usr/bin/env python3
"""Prepare/verify only the standalone hosted Quick Look fixture; never launch the product."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args):
    return subprocess.check_output(args, text=True, timeout=60).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--verify-built", action="store_true")
    parser.add_argument("--verify-finder", action="store_true")
    args = parser.parse_args()
    assert os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_OS") == "macOS"
    assert os.environ.get("GITHUB_REPOSITORY") == "Joncallim/mostlytext"
    assert Path.home() == Path("/Users/runner") and platform.mac_ver()[0].split(".")[0] == "26"
    root = args.output.resolve()
    assert root == Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-qlreply"
    receipt_path = root / "receipt.json"
    if not (args.verify_built or args.verify_finder):
        assert not root.exists()
        root.mkdir(mode=0o700)
        paths = command(["git", "ls-files", "--", ".github/quicklook-reply-probe",
                         ".github/scripts/prepare-quicklook-reply-probe.py",
                         ".github/scripts/run-owned-app-tests.py", ".github/workflows/quicklook-reply-probe.yml"]).splitlines()
        assert paths and any(p.endswith("StaticPreview.swift") for p in paths)
        fixture = root / "fixture"
        shutil.copytree(".github/quicklook-reply-probe", fixture)
        source = root / "mostlytext-ql-reply-static.md"
        source.write_bytes(b"# Hosted Quick Look fixture\n")
        (root / "ql-probe-neighbor.md").write_bytes(b"Generated sibling capability control; do not read through the provider.\n")
        record = {"checkout": command(["git", "rev-parse", "HEAD"]),
                  "source_sha256": {p: digest(Path(p)) for p in paths},
                  "fixture_source_sha256": {str(p.relative_to(fixture)): digest(p) for p in fixture.rglob("*") if p.is_file()},
                  "selected_fixture_sha256": digest(source),
                  "root_product_tree": command(["git", "rev-parse", "HEAD:MacDown2"]),
                  "xcode": command(["xcodebuild", "-version"]), "os": command(["sw_vers"]),
                  "scope": "Standalone disposable hosted static-provider feasibility; no root product launch, shipping extension, full QL-REPLY or owner acceptance"}
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
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, timeout=30)
    result = subprocess.run(["codesign", "--display", "--entitlements", "-", "--xml", str(provider)],
                            capture_output=True, check=True, timeout=30)
    raw = result.stdout
    if b"<?xml" not in raw:
        raw = result.stderr[result.stderr.index(b"<?xml"):]
    entitlements = plistlib.loads(raw[raw.index(b"<?xml"):])
    assert entitlements.get("com.apple.security.app-sandbox") is True
    assert entitlements.get("com.apple.security.files.user-selected.read-only") is True
    assert not any("network" in key or "application-groups" in key for key in entitlements)
    (root / "provider-actual-entitlements.plist").write_bytes(plistlib.dumps(entitlements))
    record["built"] = {"app_info": app_info, "provider_info": info, "entitlements": entitlements,
                       "app_executable_sha256": digest(app / "Contents/MacOS" / app_info["CFBundleExecutable"]),
                       "provider_executable_sha256": digest(provider / "Contents/MacOS" / info["CFBundleExecutable"])}
    assert digest(root / "mostlytext-ql-reply-static.md") == record["selected_fixture_sha256"]
    if args.verify_finder:
        events = json.loads((root / "provider-events.json").read_text())
        messages = [x.get("eventMessage", "") for x in events if isinstance(x, dict)]
        assert not any("container-launched-invalidates-cold-proof" in x for x in messages), "Containing fixture actually launched"
        for marker in ["QL_REPLY_PROBE callback", "QL_REPLY_PROBE selected-read", "QL_REPLY_PROBE sibling-open-admitted", "QL_REPLY_PROBE replied", "QL_REPLY_PROBE factory"]:
            assert any(marker in x for x in messages), marker
        owned = json.loads((root / "owned/status.json").read_text())
        identity = json.loads((root / "owned/identity.json").read_text())
        assert owned["returncode"] == 0 and not owned["timed_out"] and not owned["cancelled"]
        assert identity["checkout"] == record["checkout"]
        assert identity["app_sha256"] == record["built"]["provider_executable_sha256"]
        record["cold_finder_test"] = {"owned_status": owned, "actual_provider_events": [x for x in messages if "QL_REPLY_PROBE" in x],
                                      "event_log_sha256": digest(root / "provider-events.json"),
                                      "scope": "Actual visible Finder marker and static provider callback/factory only; image presentation still needs screenshot inspection; not full QL-REPLY"}
    receipt_path.write_text(json.dumps(record, indent=2) + "\n")
    print("Actual signed fixture identifiers, Markdown-only data provider, sandbox entitlements and source hashes verified")


if __name__ == "__main__":
    main()

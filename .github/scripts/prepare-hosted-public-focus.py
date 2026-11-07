#!/usr/bin/env python3
"""Prepare only a trusted disposable hosted normal-app focus journey."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import pwd
import shutil
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_host(root):
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python cannot enforce this hosted execution contract")
    assert os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_OS") == "macOS"
    assert os.environ.get("GITHUB_REPOSITORY") == "Joncallim/mostlytext"
    account = pwd.getpwuid(os.getuid())
    assert os.getuid() == os.geteuid() > 0 and account.pw_name == "runner" and account.pw_dir == "/Users/runner"
    assert Path.home() == Path("/Users/runner") and platform.machine() == "arm64"
    assert platform.mac_ver()[0].split(".")[0] == "26"
    assert root == Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-focus"
    assert str(root) == "/Users/runner/work/_temp/mostlytext-focus"
    assert not any(os.path.lexists(p) for p in ["/Users/jonathanlim", "/Users/mostlytexttest", "/Volumes/Fast SSD"])
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    if "pull_request" in event:
        assert event["pull_request"]["head"]["repo"]["full_name"] == "Joncallim/mostlytext"
    else:
        assert os.environ["GITHUB_EVENT_NAME"] == "workflow_dispatch"


def output(command):
    return subprocess.check_output(command, text=True, timeout=60).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--bind-built", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root = args.output.resolve()
    check_host(root)
    record_path = root / "receipt.json"
    if not args.bind_built and not args.verify:
        assert not root.exists()
        root.mkdir(mode=0o700)
        support = Path.home() / "Library/Application Support"
        absent = [support / "MostlyText", support / "MacDown 2"]
        assert all(not p.exists() for p in absent)
        initial = subprocess.run(["defaults", "read", "app.mostlytext.MostlyText"], capture_output=True, text=True, timeout=15)
        assert initial.returncode != 0 and "does not exist" in initial.stderr
        tracked = output(["git", "ls-files", "--", "MacDown2", ".github/hosted-public-focus",
                          ".github/scripts/prepare-hosted-public-focus.py", ".github/scripts/run-hosted-public-focus.py",
                          ".github/scripts/test-hosted-focus-guard.py", ".github/scripts/test-run-owned-app-tests.py",
                          ".github/scripts/native-cli-app-host.swift", ".github/scripts/native_cli_endpoint_probe.py",
                          ".github/scripts/run-owned-app-tests.py", ".github/workflows/hosted-public-focus.yml"]).splitlines()
        required = {".github/scripts/native-cli-app-host.swift", ".github/scripts/native_cli_endpoint_probe.py"}
        assert required <= set(tracked), "Intake actual qualified startup integration before this lane"
        shutil.copytree(".github/hosted-public-focus", root / "fixture")
        folder = root / "documents"
        folder.mkdir(mode=0o700)
        name = "focus-" + os.environ["GITHUB_RUN_ID"] + ".md"
        source = folder / name
        source.write_bytes(b"- item")
        record = {"checkout": output(["git", "rev-parse", "HEAD"]),
                  "source_sha256": {p: sha(Path(p)) for p in tracked},
                  "pins": json.loads(Path("MacDown2/Packages/MacDownKit/Package.resolved").read_text())["pins"],
                  "source_file": str(source), "source_file_sha256": sha(source),
                  "host": {"uid": os.getuid(), "account": account_name(), "os": output(["sw_vers"]),
                           "xcode": output(["xcodebuild", "-version"]), "architecture": platform.machine()},
                  "initial_product_domain": {"returncode": initial.returncode, "stderr": initial.stderr},
                  "declared_owner_paths_absent": True,
                  "scope": "Different disposable hosted machine, not CORTANA owner-denial/protected-lane or exact signed-artifact acceptance",
                  "commands": [], "errors": [], "criteria": {}}
        keyboard = subprocess.run(["defaults", "read", "com.apple.HIToolbox", "AppleSelectedInputSources"], capture_output=True, text=True, timeout=15)
        record["keyboard_source"] = {"returncode": keyboard.returncode, "stdout": keyboard.stdout, "stderr": keyboard.stderr}
        # The actual TIS/GUI source is required after the real input control, not inferred from this cache.
        record_path.write_text(json.dumps(record, indent=2) + "\n")
        return
    record = json.loads(record_path.read_text())
    assert record["checkout"] == output(["git", "rev-parse", "HEAD"])
    for name, digest in record["source_sha256"].items():
        assert sha(Path(name)) == digest, name
    assert sha(Path(record["source_file"])) == record["source_file_sha256"]
    app = root / "app/Build/Products/Release/MacDown2.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    helper = app / "Contents/MacOS/mostlytext-cli"
    assert info["CFBundleIdentifier"] == "app.mostlytext.MostlyText" and helper.is_file()
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, timeout=30)
    built = {"app": str(app), "executable": str(executable), "app_sha256": sha(executable),
             "helper": str(helper), "helper_sha256": sha(helper),
             "controller_sha256": sha(root / "normal-app-host"), "host_facts_sha256": sha(root / "host-facts"), "info": info}
    if args.bind_built:
        assert "built" not in record
        record["built"] = built
        public = root / "mostlytext"
        public.symlink_to(helper)
        record["public_cli"] = str(public)
        values = {"identity": str(root / "current-application.json"), "application": str(app),
                  "executable": str(executable), "appSHA256": built["app_sha256"],
                  "fileName": Path(record["source_file"]).name, "folder": str(Path(record["source_file"]).parent)}
        generated = "// Generated from the exact hosted build; never executed locally.\nenum HostedFocusInputs {\n"
        generated += "".join("    static let " + key + " = " + json.dumps(value) + "\n" for key, value in values.items()) + "}\n"
        (root / "fixture/Driver/HostedFocusInputs.swift").write_text(generated)
        subprocess.run(["xcodegen", "generate", "--spec", str(root / "fixture/project.yml")], check=True, timeout=60)
        record["generated_sha256"] = {str(p.relative_to(root / "fixture")): sha(p) for p in (root / "fixture").rglob("*") if p.is_file()}
        record_path.write_text(json.dumps(record, indent=2) + "\n")
    else:
        assert record["built"] == built, "Normal app/helper/controller identity changed"
        assert Path(record["public_cli"]).resolve() == helper
        for name, digest in record["generated_sha256"].items():
            assert sha(root / "fixture" / name) == digest, name
        print("Exact normal app/helper/controller, source/generated inputs, pins and document bytes unchanged")


def account_name():
    return pwd.getpwuid(os.getuid()).pw_name


if __name__ == "__main__":
    main()

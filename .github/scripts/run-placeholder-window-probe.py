#!/usr/bin/env python3
"""Record one real classifier counterexample; a baseline failure is not a product pass."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

BASELINE = "e90127e9f75df20b8be1179e6ba7730651775cb2"
METHOD = "unmarkedWindowsAreNotStartupPlaceholders"
TARGET = "MacDown2Tests/PlaceholderWindowCleanupTests/" + METHOD
PRIVATE_TEST = ".github/placeholder-window-probe/PlaceholderOwnershipProbeTests.swift"
EXECUTED_TEST = "MacDown2/MacDown2Tests/PlaceholderOwnershipProbeTests.swift"


def main():
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python is refused before placeholder probe preparation")
    spec = importlib.util.spec_from_file_location("qualified_host_guard", Path(__file__).with_name("prepare-hosted-public-focus.py"))
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    root = Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-focus"
    guard.check_host(root)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "execute"])
    parser.add_argument("--mode", choices=["reproduce-original", "verify-fix"], default="reproduce-original")
    args = parser.parse_args()
    out = lambda cmd: subprocess.check_output(cmd, text=True, timeout=60).strip()
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    receipt_path = root / "receipt.json"
    if args.stage == "prepare":
        if root.exists(): raise RuntimeError("Refuse an existing probe root")
        if args.mode == "reproduce-original":
            baseline_tree = out(["git", "rev-parse", BASELINE + ":MacDown2"])
            if out(["git", "rev-parse", "HEAD:MacDown2"]) != baseline_tree:
                raise RuntimeError("The baseline counterexample requires byte-identical qualified product source")
        root.mkdir(mode=0o700)
        paths = out(["git", "ls-files", "--", "MacDown2", ".github/placeholder-window-probe",
                     ".github/scripts/run-placeholder-window-probe.py", ".github/scripts/prepare-hosted-public-focus.py",
                     ".github/scripts/test-hosted-focus-guard.py", ".github/scripts/run-owned-app-tests.py",
                     ".github/scripts/test-run-owned-app-tests.py", ".github/workflows/placeholder-window-probe.yml"]).splitlines()
        record = {"checkout": out(["git", "rev-parse", "HEAD"]), "mode": args.mode,
                  "canonical_source_sha256": {p: sha(Path(p)) for p in paths},
                  "pins": json.loads(Path("MacDown2/Packages/MacDownKit/Package.resolved").read_text())["pins"],
                  "selected": TARGET, "host": {"uid": os.getuid(), "os": out(["sw_vers"]), "xcode": out(["xcodebuild", "-version"])},
                  "scope": "One component classifier regression on another disposable machine; not native gestures/critical suite/protected owner or signed artifact acceptance"}
        destination = Path(EXECUTED_TEST)
        if destination.exists():
            if destination.read_bytes() != Path(PRIVATE_TEST).read_bytes(): raise RuntimeError("Canonical and controlled regression differ")
            addition = False
        else:
            shutil.copyfile(PRIVATE_TEST, destination)
            addition = True
        record["controlled_test_input"] = {"source": PRIVATE_TEST, "executed": EXECUTED_TEST, "sha256": sha(destination), "canonical_addition": addition}
        record["executed_source_sha256"] = dict(record["canonical_source_sha256"], **{EXECUTED_TEST: sha(destination)})
        receipt_path.write_text(json.dumps(record, indent=2) + "\n")
        return
    record = json.loads(receipt_path.read_text())
    if record["mode"] != args.mode or record["checkout"] != out(["git", "rev-parse", "HEAD"]):
        raise RuntimeError("Changed probe mode or source")
    for p, h in record["executed_source_sha256"].items():
        if sha(Path(p)) != h: raise RuntimeError("Changed executed source: " + p)
    app = root / "app/Build/Products/Debug/MacDown2.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != "app.mostlytext.MostlyText": raise RuntimeError("Wrong component app identity")
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    record["built"] = {"app": str(app), "executable_sha256": sha(executable), "info": info}
    plans = list((root / "app/Build/Products").glob("*.xctestrun"))
    if not plans: raise RuntimeError("No actual generated test plan")
    record["xctestrun_sha256"] = {str(p.relative_to(root)): sha(p) for p in plans}
    command = ["python3", ".github/scripts/run-owned-app-tests.py", str(root / "probe-owned"), str(executable), "--",
               "xcodebuild", "-project", "MacDown2/MacDown2.xcodeproj", "-scheme", "MacDown2", "-configuration", "Debug",
               "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(root / "app"), "-onlyUsePackageVersionsFromResolvedFile",
               "-enableCodeCoverage", "NO", "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
               "-default-test-execution-time-allowance", "120", "-maximum-test-execution-time-allowance", "120",
               "-resultBundlePath", str(root / "Probe.xcresult"), "-only-testing:" + TARGET, "test-without-building"]
    record["command"] = command
    receipt_path.write_text(json.dumps(record, indent=2) + "\n")
    with (root / "probe.log").open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    record["command_returncode"] = result.returncode
    record["owned"] = json.loads((root / "probe-owned/status.json").read_text())
    receipt_path.write_text(json.dumps(record, indent=2) + "\n")
    summary = json.loads(out(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(root / "Probe.xcresult")]))
    record["actual_summary"] = summary
    expected = {"totalTestCount": 1, "passedTests": 0 if args.mode == "reproduce-original" else 1,
                "failedTests": 1 if args.mode == "reproduce-original" else 0, "skippedTests": 0, "expectedFailures": 0}
    owned = record["owned"]
    expected_code = 65 if args.mode == "reproduce-original" else 0
    count_match = all(type(summary.get(k)) is int and summary[k] == v for k, v in expected.items())
    if args.mode == "reproduce-original":
        failures = summary.get("testFailures", [])
        identity_match = (len(failures) == 1 and METHOD in json.dumps(failures[0])
                          and "isSwiftUIPlaceholder" in failures[0].get("failureText", ""))
    else:
        identity_match = bool(re.search(r"Test " + METHOD + r"\(\) passed", (root / "probe.log").read_text()))
    record["controlled_outcome_verified"] = (count_match and identity_match and result.returncode == owned["returncode"] == expected_code
                                             and owned["timed_out"] is False and owned["cancelled"] is False)
    for p, h in record["executed_source_sha256"].items():
        if sha(Path(p)) != h: raise RuntimeError("Source changed during actual component execution")
    record["source_verified_after"] = True
    receipt_path.write_text(json.dumps(record, indent=2) + "\n")
    if not record["controlled_outcome_verified"]:
        raise RuntimeError("The exact intended classifier outcome was not observed; keep the first outcome unchanged")
    print("Actual controlled component outcome verified:", args.mode, "; not a native/product/release pass")


if __name__ == "__main__":
    main()

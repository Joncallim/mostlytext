#!/usr/bin/env python3
"""Capture actual SDK test enumeration after the qualified focus bootstrap."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

QUALIFIED_MAIN = "aff49a5eb4b7bb111ce949daef66b0b41ddfb274"
EXTRA_INPUTS = [".github/scripts/run-hosted-critical-discovery.py",
                ".github/scripts/test-hosted-critical-discovery.py",
                ".github/workflows/hosted-critical-discovery.yml"]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contract():
    inventory = json.loads(Path("planning/downstream/native-ui-required-cases.json").read_text())
    validator = module("discovery_source_inventory", "check-native-ui-required-cases.py")
    counts = validator.validate(Path.cwd(), inventory)
    if counts["declared_source_cases"] != 38 or counts["retained_original_behavior_ids"] != 38:
        raise RuntimeError("Reconcile the retained inventory before discovery")
    return {"kind": "raw-critical-test-discovery", "qualified_main": QUALIFIED_MAIN,
            "expected_source_ids_not_execution_results": sorted(c["id"] for c in inventory["cases"]),
            "scope": "One genuine known focus bootstrap, then SDK enumeration; not38-case execution or final acceptance"}


def main():
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python is refused before discovery preparation")
    if not re.fullmatch(r"[0-9a-f]{40}", QUALIFIED_MAIN):
        raise RuntimeError("Critical discovery is held until verified PR124 qualification and actual main intake")
    if len(sys.argv) != 2 or sys.argv[1] not in ["prepare", "execute"]:
        raise RuntimeError("Select exactly prepare or execute")
    root = Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-focus"
    guard = module("discovery_host_guard", "prepare-hosted-public-focus.py")
    guard.check_host(root)
    base = module("discovery_known_focus", "run-hosted-original-focus.py")
    base.QUALIFIED_MAIN = QUALIFIED_MAIN
    receipt_path = root / "receipt.json"
    if sys.argv[1] == "prepare":
        base.main()
        record = json.loads(receipt_path.read_text())
        record["discovery_contract"] = contract()
        record["overall_discovery_capture_passed"] = False
        for name in EXTRA_INPUTS:
            record["source_sha256"][name] = sha(Path(name))
        receipt_path.write_text(json.dumps(record, indent=2) + "\n")
        return
    record = json.loads(receipt_path.read_text())
    if record.get("discovery_contract") != contract() or record.get("selected_original") != base.SELECTED:
        raise RuntimeError("The prepared discovery/bootstrap binding differs")
    if record.get("overall_discovery_capture_passed") is not False or "results" in record:
        raise RuntimeError("Refuse a previously attempted discovery root; preserve its first outcome")
    base.main()  # Unchanged real positive, actual original focus, target/input checks.
    record = json.loads(receipt_path.read_text())
    if record.get("passed") is not True:
        raise RuntimeError("Actual known-focus bootstrap did not qualify")
    record["bootstrap_focus_passed"] = record.pop("passed")
    record["passed"] = False
    record["raw_discovery_capture"] = {"completed": False, "actual_ids_independently_reviewed": False,
                                       "all38_cases_executed": False}

    def save():
        receipt_path.write_text(json.dumps(record, indent=2) + "\n")

    save()  # A later failure must never leave the bootstrap's passed state.
    app = root / "app/Build/Products/Debug/MacDown2.app"
    executable = app / "Contents/MacOS/MacDown2"
    raw = root / "discovered-tests.json"
    arguments = [sys.executable, ".github/scripts/run-owned-app-tests.py", str(root / "discovery-owned"), str(executable), "--",
                 "xcodebuild", "-project", "MacDown2/MacDown2.xcodeproj", "-scheme", "MacDown2", "-configuration", "Debug",
                 "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(root / "app"),
                 "-onlyUsePackageVersionsFromResolvedFile", "-enableCodeCoverage", "NO", "-parallel-testing-enabled", "NO",
                 "-only-testing:MacDown2UITests", "-enumerate-tests", "-test-enumeration-style", "flat",
                 "-test-enumeration-format", "json", "-test-enumeration-output-path", str(raw), "test-without-building"]
    try:
        with (root / "discovery.log").open("w") as log:
            result = subprocess.run(arguments, stdout=log, stderr=subprocess.STDOUT)
        owned = json.loads((root / "discovery-owned/status.json").read_text())
        record["commands"].append({"label": "raw-critical-discovery", "arguments": arguments,
                                   "returncode": result.returncode, "owned": owned})
        save()
        if result.returncode or owned["returncode"] or owned["timed_out"] or owned["cancelled"]:
            raise RuntimeError("SDK discovery has a genuine failed owned outcome")
        value = json.loads(raw.read_text())
        if not isinstance(value, (dict, list)) or not value:
            raise RuntimeError("Retain and inspect the SDK's unexpected empty enumeration response")
        for name, digest in record["source_sha256"].items():
            if sha(Path(name)) != digest:
                raise RuntimeError("Changed canonical source: " + name)
        for name, digest in record["generated_sha256"].items():
            if sha(root / "fixture" / name) != digest:
                raise RuntimeError("Changed generated input: " + name)
        if sha(executable) != record["built_after"]["executable_sha256"]:
            raise RuntimeError("Actual Debug app changed after bootstrap")
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info != record["built_after"]["info"]:
            raise RuntimeError("Actual Debug metadata changed after bootstrap")
        for name, digest in record["actual_xctestruns"].items():
            if sha(root / name) != digest:
                raise RuntimeError("Actual configured test target changed during enumeration")
        test = root / "app/Build/Products/Debug/MacDown2UITests-Runner.app/Contents/PlugIns/MacDown2UITests.xctest/Contents/MacOS/MacDown2UITests"
        if sha(test) != record["test_executable_sha256"]:
            raise RuntimeError("Actual original test input changed during enumeration")
        signature = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True, text=True, timeout=30)
        record["commands"].append({"label": "post-discovery-signature", "arguments": signature.args,
                                   "returncode": signature.returncode, "stderr": signature.stderr[:131072]})
        if signature.returncode:
            raise RuntimeError("Actual Debug signature/resource verification failed after enumeration")
        record["raw_discovery_capture"].update(completed=True, path=str(raw), sha256=sha(raw),
                                                root_json_type=type(value).__name__, unchanged_inputs_after=True,
                                                scope="Raw SDK enumeration captured; exact schema and38IDs need independent review before batch implementation")
        record["passed"] = True
        record["overall_discovery_capture_passed"] = True
    except Exception as error:
        record["errors"].append({"type": type(error).__name__, "message": str(error)[:4096]})
    finally:
        save()
    if not record["overall_discovery_capture_passed"]:
        raise RuntimeError("Discovery did not qualify; preserve the complete first outcome")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Execute one fixed, source-bound original UI batch on a fresh disposable host."""
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

from native_ui_discovery import selected_batch

BATCH_KEYS = tuple(f"B{i:02d}" for i in range(1, 11))
QUALIFIED_MAIN = "210f46b7f94fdbbf0e8dcc14f2a3cd6c1b306ab3"


def require_exact_case_outcome(summary, owned, returncode, log, selected_case):
    if type(returncode) is not int or type(owned.get("returncode")) is not int:
        raise RuntimeError(selected_case + " has non-integer command outcomes")
    if owned["timed_out"] or owned["cancelled"] or owned["app_cleanup_requested"]:
        raise RuntimeError(selected_case + " has timeout, cancellation or cleanup uncertainty")
    expected = {"totalTestCount": 1, "skippedTests": 0, "expectedFailures": 0}
    if any(type(summary.get(k)) is not int for k in ["passedTests", "failedTests"]):
        raise RuntimeError(selected_case + " has non-integer native result counts")
    if any(type(summary.get(k)) is not int or summary[k] != v for k, v in expected.items()):
        raise RuntimeError(selected_case + " did not execute exactly one unskipped selected case")
    passed = (summary.get("passedTests") == 1 and summary.get("failedTests") == 0
              and returncode == owned["returncode"] == 0)
    failed = (summary.get("passedTests") == 0 and summary.get("failedTests") == 1
              and returncode == owned["returncode"] == 65)
    if not passed and not failed:
        raise RuntimeError(selected_case + " has an unclassified count or owned command outcome")
    selected_class, selected_method = selected_case.split("/")[1:]
    pattern = r"Test Case '-\[" + re.escape(selected_case.split("/")[0]) + r"\." + re.escape(selected_class) + " " + re.escape(selected_method) + r"\]' "
    if (len(re.findall(pattern + "started", log)) != 1
            or len(re.findall(pattern + ("passed" if passed else "failed"), log)) != 1
            or re.search(pattern + ("failed" if passed else "passed"), log)
            or "Restarting after unexpected" in log):
        raise RuntimeError(selected_case + " actual case identity/repetition differs or framework restarted")
    return passed


def main():
    # Refuse before parsing or filesystem preparation; reused guard also refuses -O.
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python is refused before original UI-batch preparation")
    if not re.fullmatch(r"[0-9a-f]{40}", QUALIFIED_MAIN):
        raise RuntimeError("UI-batch execution is held until verified SDK calibration and actual main intake")
    spec = importlib.util.spec_from_file_location("normal_focus_guard", Path(__file__).with_name("prepare-hosted-public-focus.py"))
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    root = Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-focus"
    guard.check_host(root)
    subprocess.run(["git", "merge-base", "--is-ancestor", QUALIFIED_MAIN, "HEAD"], check=True, timeout=15)
    if len(sys.argv) != 3 or sys.argv[1] not in ["prepare", "execute"] or sys.argv[2] not in BATCH_KEYS:
        raise RuntimeError("Select prepare or execute and exactly one fixed batch")
    contract = selected_batch(Path.cwd(), sys.argv[2])
    selected = contract["cases"][0]
    output = lambda args: subprocess.check_output(args, text=True, timeout=60).strip()
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    mapping = {
        ".github/hosted-public-focus/Control/main.swift": "Control/main.swift",
        ".github/hosted-public-focus/Control-Info.plist": "Control-Info.plist",
        ".github/hosted-public-focus/project.yml": "project.yml",
        ".github/hosted-original-focus/PositiveTests.swift": "Driver/PublicFocusTests.swift",
    }
    if sys.argv[1] == "prepare":
        if root.exists():
            raise RuntimeError("Refuse an existing original-focus root")
        for name in ["MostlyText", "MacDown 2"]:
            if (Path.home() / "Library/Application Support" / name).exists():
                raise RuntimeError("Fresh product data is required")
        domain = subprocess.run(["defaults", "read", "app.mostlytext.MostlyText"], capture_output=True, text=True, timeout=15)
        if domain.returncode == 0 or "does not exist" not in domain.stderr:
            raise RuntimeError("Fresh product preferences are required")
        root.mkdir(mode=0o700)
        paths = output(["git", "ls-files", "--", "MacDown2", ".github/hosted-original-focus",
                        ".github/hosted-public-focus", ".github/scripts/prepare-hosted-public-focus.py",
                        ".github/scripts/run-hosted-original-focus.py", ".github/scripts/run-owned-app-tests.py",
                        ".github/scripts/test-hosted-focus-guard.py", ".github/scripts/test-run-owned-app-tests.py",
                        ".github/scripts/check-native-ui-required-cases.py", ".github/scripts/test-native-ui-required-cases.py",
                        "planning/downstream/native-ui-required-cases.json",
                        ".github/workflows/hosted-original-focus.yml", ".github/scripts/run-hosted-ui-batch.py",
                        ".github/scripts/test-hosted-ui-batch.py", ".github/scripts/native_ui_discovery.py",
                        ".github/scripts/test-native-ui-discovery.py", ".github/workflows/hosted-ui-matrix.yml",
                        "planning/downstream/native-ui-hosted-batches.json",
                        "planning/downstream/evidence/critical-sdk-discovery-2026-11-07/actual-discovered-tests.json"]).splitlines()
        for source, target in mapping.items():
            p = root / "fixture" / target
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, p)
        subprocess.run(["xcodegen", "generate", "--spec", str(root / "fixture/project.yml")], check=True, timeout=60)
        record = {"checkout": output(["git", "rev-parse", "HEAD"]), "source_sha256": {p: sha(Path(p)) for p in paths},
                  "pins": json.loads(Path("MacDown2/Packages/MacDownKit/Package.resolved").read_text())["pins"],
                  "generated_sha256": {str(p.relative_to(root / "fixture")): sha(p) for p in (root / "fixture").rglob("*") if p.is_file()},
                  "fixture_mapping": mapping, "selected_original": selected, "batch_contract": contract,
                  "batch_cases": [{"selected": case, "status": "NOT_RUN", "reason": "Not yet executed"}
                                  for case in contract["cases"]], "passed": False, "execution_started": False, "commands": [], "errors": [],
                  "host": {"os": output(["sw_vers"]), "xcode": output(["xcodebuild", "-version"]), "uid": os.getuid()},
                  "initial_domain": {"returncode": domain.returncode, "stderr": domain.stderr},
                  "scope": "Intentional ordinary Debug original-case engineering, not protected CORTANA, ordinary Release, performance or signed-artifact acceptance"}
        (root / "receipt.json").write_text(json.dumps(record, indent=2) + "\n")
        return
    record_path = root / "receipt.json"
    record = json.loads(record_path.read_text())
    if record.get("batch_contract") != contract or "results" in record or record.get("execution_started") is not False:
        raise RuntimeError("Refuse a changed contract or previously attempted batch root")
    if record.get("batch_cases") != [{"selected": case, "status": "NOT_RUN", "reason": "Not yet executed"}
                                     for case in contract["cases"]]:
        raise RuntimeError("Refuse retargeted or previously attempted original cases")

    def save(): record_path.write_text(json.dumps(record, indent=2) + "\n")

    record["execution_started"] = True
    save()  # Freeze this first attempt before source/product/positive commands.

    def verify_sources():
        if record["checkout"] != output(["git", "rev-parse", "HEAD"]):
            raise RuntimeError("Changed checkout")
        for p, h in record["source_sha256"].items():
            if sha(Path(p)) != h: raise RuntimeError("Changed source: " + p)
        for p, h in record["generated_sha256"].items():
            if sha(root / "fixture" / p) != h: raise RuntimeError("Changed control input: " + p)

    def command(label, args, timeout=30):
        result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
        record["commands"].append({"label": label, "arguments": [str(a) for a in args], "returncode": result.returncode,
                                   "stdout": result.stdout[:131072], "stderr": result.stderr[:131072]})
        save()
        if result.returncode: raise RuntimeError(label + " failed")
        return result.stdout

    def app_metadata(label, app):
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != "app.mostlytext.MostlyText":
            raise RuntimeError("Unexpected Debug application identity")
        command(label + "-signature", ["codesign", "--verify", "--deep", "--strict", app])
        details = subprocess.run(["codesign", "--display", "--verbose=4", "--entitlements", "-", "--xml", str(app)], capture_output=True, timeout=30)
        if details.returncode: raise RuntimeError("Cannot record actual Debug signing context")
        (root / (label + "-signature.txt")).write_bytes(details.stdout + details.stderr)
        return {"path": str(app), "executable_sha256": sha(app / "Contents/MacOS" / info["CFBundleExecutable"]), "info": info}

    def phase(label, app_executable, arguments, expected_case):
        args = ["python3", ".github/scripts/run-owned-app-tests.py", str(root / (label + "-owned")), str(app_executable), "--", *arguments]
        with (root / (label + ".log")).open("w") as log:
            result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT)
        record["commands"].append({"label": label, "arguments": args, "returncode": result.returncode})
        save()
        summary = json.loads(command(label + "-summary", ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", root / (label + ".xcresult")]))
        (root / (label + "-summary.json")).write_text(json.dumps(summary, indent=2) + "\n")
        owned = json.loads((root / (label + "-owned/status.json")).read_text())
        record.setdefault("results", {})[label] = {"summary": summary, "owned": owned, "selected": expected_case}
        save()
        passed = require_exact_case_outcome(summary, owned, result.returncode,
                                            (root / (label + ".log")).read_text(), expected_case)
        record["results"][label]["passed"] = passed
        save()
        return passed

    app = root / "app/Build/Products/Debug/MacDown2.app"
    try:
        verify_sources()
        record["built_before"] = app_metadata("before", app)
        settings = json.loads((root / "root-build-settings.json").read_text())
        build = next(s["buildSettings"] for s in settings if s["target"] == "MacDown2")
        if build["CONFIGURATION"] != "Debug" or "DEBUG" not in build["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split() or "UITEST_ISOLATED" in build["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split():
            raise RuntimeError("This must be intentional ordinary Debug, not Release or the protected isolated configuration")
        if Path(build["TARGET_BUILD_DIR"]) / build["FULL_PRODUCT_NAME"] != app:
            raise RuntimeError("Actual target application path differs from the built Debug app")
        record["actual_build_configuration"] = {k: build.get(k) for k in ["CONFIGURATION", "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "TARGET_BUILD_DIR", "FULL_PRODUCT_NAME", "PRODUCT_BUNDLE_IDENTIFIER"]}
        record["actual_xctestruns"] = {str(p.relative_to(root)): sha(p) for p in (root / "app/Build/Products").glob("*.xctestrun")}
        if not record["actual_xctestruns"]: raise RuntimeError("Missing actual root xctestrun")
        targets = []
        def collect_targets(value):
            if isinstance(value, dict):
                if value.get("IsUITestBundle") is True: targets.append(value)
                for child in value.values(): collect_targets(child)
            elif isinstance(value, list):
                for child in value: collect_targets(child)
        for name in record["actual_xctestruns"]:
            collect_targets(plistlib.loads((root / name).read_bytes()))
        matched = [t for t in targets if str(t.get("TestBundlePath", "")).endswith("MacDown2UITests.xctest")]
        if len(matched) != 1: raise RuntimeError("Expected exactly one actual original UI target")
        target_path = matched[0]["UITargetAppPath"].replace("__TESTROOT__", str(root / "app/Build/Products"))
        if Path(target_path) != app: raise RuntimeError("Actual xctestrun target is not the built ordinary Debug app")
        test_host = Path(matched[0]["TestHostPath"].replace("__TESTROOT__", str(root / "app/Build/Products")))
        if test_host != root / "app/Build/Products/Debug/MacDown2UITests-Runner.app":
            raise RuntimeError("Unexpected actual UI test host")
        test_bundle = Path(matched[0]["TestBundlePath"].replace("__TESTHOST__", str(test_host)).replace("__TESTROOT__", str(root / "app/Build/Products")))
        if test_bundle != test_host / "Contents/PlugIns/MacDown2UITests.xctest":
            raise RuntimeError("Unexpected actual original test bundle")
        test_binary = test_bundle / "Contents/MacOS/MacDown2UITests"
        record["test_executable_sha256"] = sha(test_binary)
        record["actual_original_target"] = {k: matched[0].get(k) for k in ["TestHostPath", "TestBundlePath", "UITargetAppPath", "IsUITestBundle"]}
        (root / "test-inputs").mkdir()
        shutil.copyfile(test_binary, root / "test-inputs/MacDown2UITests")
        common = ["-configuration", "Release", "-destination", "platform=macOS", "-derivedDataPath", str(root / "control"),
                  "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120", "-maximum-test-execution-time-allowance", "120"]
        positive_passed = phase("positive", root / "control/Build/Products/Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl",
              ["xcodebuild", "-project", str(root / "fixture/HostedPublicFocus.xcodeproj"), "-scheme", "HostedPublicFocus", *common,
               "-resultBundlePath", str(root / "positive.xcresult"), "-only-testing:HostedFocusDriverTests/OriginalFocusPositiveTests/testActualTypingAndButtonBeforeOriginalAppCase", "test-without-building"],
              "HostedFocusDriverTests/OriginalFocusPositiveTests/testActualTypingAndButtonBeforeOriginalAppCase")
        if not positive_passed:
            raise RuntimeError("The genuine input control failed; no root original case may execute")
        record["actual_gui"] = json.loads(command("actual-gui-facts", [root / "host-facts"]))
        save()
        facts = record["actual_gui"]
        if not (facts.get("on_console") is True and facts.get("login_done") is True
                and facts.get("uid") == os.getuid() and facts.get("screen_lock_field") is not True
                and facts.get("keyboard_input_source") == "com.apple.keylayout.US" and facts.get("screens")):
            raise RuntimeError("Actual GUI/input facts do not admit original app execution")
        for index, row in enumerate(record["batch_cases"]):
            case = row["selected"]
            label = f"case-{index + 1:02d}"
            row.update(status="RUNNING", reason="Actual named case executing", result_label=label)
            save()
            verify_sources()
            passed = phase(label, app / "Contents/MacOS/MacDown2",
                  ["xcodebuild", "-project", "MacDown2/MacDown2.xcodeproj", "-scheme", "MacDown2", "-configuration", "Debug",
                   "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(root / "app"), "-onlyUsePackageVersionsFromResolvedFile", "-enableCodeCoverage", "NO",
                   "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120", "-maximum-test-execution-time-allowance", "120",
                   "-resultBundlePath", str(root / (label + ".xcresult")), "-only-testing:" + case, "test-without-building"], case)
            verify_sources()
            for name, digest in record["actual_xctestruns"].items():
                if sha(root / name) != digest:
                    raise RuntimeError("Actual compiled xctestrun changed after " + case)
            if sha(test_binary) != record["test_executable_sha256"]:
                raise RuntimeError("Actual original test binary changed after " + case)
            after = app_metadata(label + "-after", app)
            if after != record["built_before"]:
                raise RuntimeError("Actual application changed after " + case)
            row.update(status="PASSED" if passed else "FAILED",
                       reason="Actual sole named case passed" if passed else "Actual sole named case failed",
                       source_and_products_verified_after=True, app_after=after)
            save()
        verify_sources()
        record["source_unchanged_after"] = True
    except Exception as error:
        record["errors"].append({"type": type(error).__name__, "message": str(error)[:4096]})
        for row in record["batch_cases"]:
            if row["status"] in ["NOT_RUN", "RUNNING"]:
                row.update(status="NOT_RUN" if row["status"] == "NOT_RUN" else "INCOMPLETE",
                           reason="Stopped after " + type(error).__name__ + ": " + str(error)[:512])
    finally:
        if app.exists():
            try: record["built_after"] = app_metadata("after", app)
            except Exception as error: record["errors"].append({"type": type(error).__name__, "message": str(error)[:4096]})
        record["passed"] = (not record["errors"] and record.get("source_unchanged_after") is True
                            and record.get("results", {}).get("positive", {}).get("passed") is True
                            and all(row["status"] == "PASSED" and row.get("source_and_products_verified_after") is True
                                    for row in record["batch_cases"]))
        save()
    if not record["passed"]:
        raise RuntimeError("Original UI batch did not qualify; preserve every actual first case outcome")


if __name__ == "__main__":
    main()

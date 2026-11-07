#!/usr/bin/env python3
"""Gate a normal external app launch on an actual benign hosted input control."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from native_cli_endpoint_probe import probe_endpoint


def main():
    root = Path(sys.argv[1]).resolve()
    spec = importlib.util.spec_from_file_location("focus_preparation", Path(__file__).with_name("prepare-hosted-public-focus.py"))
    preparation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preparation)
    preparation.check_host(root)
    path = root / "receipt.json"
    receipt = json.loads(path.read_text())
    current = None

    def persist():
        path.write_text(json.dumps(receipt, indent=2) + "\n")

    def command(label, arguments, timeout=30):
        result = subprocess.run([str(a) for a in arguments], capture_output=True, text=True, timeout=timeout)
        row = {"label": label, "command": [str(a) for a in arguments], "returncode": result.returncode,
               "stdout": result.stdout[:131072], "stderr": result.stderr[:131072]}
        receipt["commands"].append(row)
        persist()
        return row

    def app_action(operation, identity=None):
        args = [root / "normal-app-host", operation, receipt["built"]["app"]]
        if identity is not None:
            args += [str(identity["pid"]), str(identity["birth"])]
        result = command("app-" + operation, args)
        assert result["returncode"] == 0, result
        value = json.loads(result["stdout"])
        receipt.setdefault("applications", []).append(value)
        persist()
        return value

    def ui_phase(label, method):
        control = root / "control/Build/Products/Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl"
        identifier = "HostedFocusDriverTests/PublicFocusTests/" + method
        args = ["python3", ".github/scripts/run-owned-app-tests.py", str(root / (label + "-owned")), str(control), "--",
                "xcodebuild", "-project", str(root / "fixture/HostedPublicFocus.xcodeproj"), "-scheme", "HostedPublicFocus",
                "-configuration", "Release", "-destination", "platform=macOS", "-derivedDataPath", str(root / "control"),
                "-resultBundlePath", str(root / (label + ".xcresult")), "-parallel-testing-enabled", "NO",
                "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120",
                "-maximum-test-execution-time-allowance", "120", "-only-testing:" + identifier, "test-without-building"]
        with (root / (label + ".log")).open("w") as log:
            result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT)
        receipt["commands"].append({"label": label, "command": args, "returncode": result.returncode})
        summary_result = command(label + "-summary", ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", root / (label + ".xcresult")])
        assert summary_result["returncode"] == 0
        summary = json.loads(summary_result["stdout"])
        (root / (label + "-summary.json")).write_text(json.dumps(summary, indent=2) + "\n")
        owned = json.loads((root / (label + "-owned/status.json")).read_text())
        receipt.setdefault("ui_results", {})[label] = {"summary": summary, "owned": owned, "selected": identifier}
        persist()
        expected = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        assert result.returncode == 0 and owned["returncode"] == 0 and not owned["timed_out"] and not owned["cancelled"]
        assert all(type(summary.get(k)) is int and summary[k] == v for k, v in expected.items()), summary
        assert method in (root / (label + ".log")).read_text()
        return True

    try:
        command("source-and-build-verification-before", ["python3", ".github/scripts/prepare-hosted-public-focus.py", root, "--verify"])
        assert receipt["commands"][-1]["returncode"] == 0
        receipt["criteria"]["benign_control"] = ui_phase("positive", "testBenignInputControl")
        facts = command("actual-gui-metadata", [root / "host-facts"])
        assert facts["returncode"] == 0
        receipt["actual_gui"] = json.loads(facts["stdout"])
        persist()
        # The normal app is never launched before the actual positive control succeeds.
        current = app_action("launch")
        (root / "current-application.json").write_text(json.dumps(current, indent=2) + "\n")
        location = Path(subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()).resolve()
        import hashlib
        endpoint = location / ("mt-" + hashlib.sha256(b"app.mostlytext.MostlyText").hexdigest()[:24]) / "s"
        deadline = time.monotonic() + 10
        attempts = []
        ready = False
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            observed = probe_endpoint(endpoint, current["pid"], min(0.05, remaining))
            attempts.append(observed)
            if observed["ready"]:
                ready = True
                break
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        receipt["live_endpoint"] = {"pid": current["pid"], "attempts": attempts, "ready": ready, "application_frames_sent": 0}
        persist()
        assert ready, "Normal app did not produce its actual live peer within the original10s"
        opened = command("public-file-open", [receipt["public_cli"], receipt["source_file"]])
        receipt["criteria"]["file_open_acknowledged"] = opened["returncode"] == 0
        assert opened["returncode"] == 0
        receipt["criteria"]["public_focus_bold_undo"] = ui_phase("focus", "testNormalPublicFocusBoldAndUndo")
        inspection = app_action("inspect", current)
        assert inspection["pid"] == current["pid"] and inspection["executable"] == current["executable"]
        checked = command("source-and-build-verification-after", ["python3", ".github/scripts/prepare-hosted-public-focus.py", root, "--verify"])
        receipt["criteria"]["unchanged_product_and_source"] = checked["returncode"] == 0
        assert checked["returncode"] == 0
        ending = app_action("terminate", current)
        receipt["criteria"]["normal_identity_bound_quit"] = ending["terminated"]
        assert ending["terminated"]
        current = None
    except Exception as error:
        receipt["errors"].append({"type": type(error).__name__, "message": str(error)[:4096]})
    finally:
        if current is not None:
            try:
                app_action("inspect", current)
                app_action("cleanup", current)
            except Exception as error:
                receipt.setdefault("cleanup_errors", []).append(str(error)[:4096])
        receipt["passed"] = (not receipt["errors"] and len(receipt["criteria"]) == 5 and all(receipt["criteria"].values()))
        persist()
    assert receipt["passed"], receipt["errors"]


if __name__ == "__main__":
    main()

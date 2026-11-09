#!/usr/bin/env python3
"""Exercise the ordinary Release export panel after a real harmless input control."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import re
import hashlib
from html.parser import HTMLParser

from native_cli_endpoint_probe import probe_endpoint


class ExportHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.text = []
        self.structural = {key: [] for key in ["h1", "strong", "code", "th", "td"]}

    def handle_starttag(self, tag, attrs):
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in self.stack:
            self.stack = self.stack[:len(self.stack) - 1 - self.stack[::-1].index(tag)]

    def handle_data(self, data):
        self.text.append(data)
        for tag in self.structural:
            if tag in self.stack:
                self.structural[tag].append(data)


def validate_html(raw):
    if not 0 < len(raw) < 16 * 1024 * 1024:
        raise RuntimeError("Invalid actual HTML output size")
    parser = ExportHTML()
    parser.feed(raw.decode("utf-8", errors="strict"))
    for tag, values in {"h1": ["NATIVE_EXPORT_CANARY"], "strong": ["bold"], "code": ["code"], "th": ["Key", "Value"], "td": ["alpha", "beta"]}.items():
        if any(value not in parser.structural[tag] for value in values):
            raise RuntimeError("Actual HTML lacks exported Markdown structure: " + tag)
    if "café" not in "".join(parser.text):
        raise RuntimeError("Actual HTML lost UTF-8 document text")
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "actual_heading_emphasis_code_and_GFM_table": True}


def validate_outputs(root, receipt, command):
    row = receipt["ordinary_export"]
    folder = root / "documents"
    expected = {Path(row[key]).name for key in ["source", "html", "pdf"]}
    if {p.name for p in folder.iterdir()} != expected:
        raise RuntimeError("Missing or unexpected actual export output, including any cancelled file")
    for key in ["source", "html", "pdf"]:
        path = Path(row[key])
        if path.parent != folder or path.is_symlink() or not path.is_file():
            raise RuntimeError("Actual export output is not a regular fixed private file")
    if Path(row["source"]).read_bytes() != preparation_source():
        raise RuntimeError("Source bytes changed after actual UI export")
    html = validate_html(Path(row["html"]).read_bytes())
    pdf = command("actual-pdfkit-output-validation", [root / "validate-export-pdf", row["pdf"]])
    assert pdf["returncode"] == 0
    result = json.loads(pdf["stdout"])
    raw = Path(row["pdf"]).read_bytes()
    if result["bytes"] != len(raw) or result["sha256"] != hashlib.sha256(raw).hexdigest():
        raise RuntimeError("PDFKit result differs from actual saved output bytes")
    spec = importlib.util.spec_from_file_location(
        "placed_pdf_canary", Path(__file__).with_name("verify-placed-pdf-canary.py")
    )
    placement = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(placement)
    measured = placement.evaluate(result)
    if not measured["short_fixture_accepted"]:
        raise RuntimeError("Actual PDF has an unexpected page or misplaced heading")
    result["placement"] = measured
    return {"html": html, "pdf": result, "source_sha256": hashlib.sha256(Path(row["source"]).read_bytes()).hexdigest()}


def preparation_source():
    spec = importlib.util.spec_from_file_location("export_preparation", Path(__file__).with_name("prepare-ordinary-export-acceptance.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.SOURCE


def main():
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python is refused before public-UI preparation")
    if len(sys.argv) != 2:
        raise RuntimeError("Select the exact guarded private export root")
    root = Path(sys.argv[1]).resolve()
    spec = importlib.util.spec_from_file_location("focus_preparation", Path(__file__).with_name("prepare-ordinary-export-acceptance.py"))
    preparation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preparation)
    preparation.preparation().check_host(root)
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

    def ui_phase(label, method, case="PublicFocusTests"):
        control = root / "control/Build/Products/Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl"
        identifier = "HostedFocusDriverTests/" + case + "/" + method
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
        assert result.returncode == 0 and owned["returncode"] == 0 and not owned["timed_out"] and not owned["cancelled"] and owned["app_cleanup_requested"] == []
        assert all(type(summary.get(k)) is int and summary[k] == v for k, v in expected.items()), summary
        pattern = r"Test Case '-\[HostedFocusDriverTests\." + re.escape(case) + " " + re.escape(method) + r"\]' passed"
        if not re.search(pattern, (root / (label + ".log")).read_text()):
            raise RuntimeError("Actual passing case differs from the selected public journey")
        checked = command(label + "-source-and-compiled-after", ["python3", ".github/scripts/prepare-ordinary-export-acceptance.py", root, "--verify"])
        assert checked["returncode"] == 0
        return True

    try:
        command("source-and-build-verification-before", ["python3", ".github/scripts/prepare-ordinary-export-acceptance.py", root, "--verify"])
        assert receipt["commands"][-1]["returncode"] == 0
        receipt["criteria"]["benign_control"] = ui_phase("positive", "testBenignInputControl")
        facts = command("actual-gui-metadata", [root / "host-facts"])
        assert facts["returncode"] == 0
        receipt["actual_gui"] = json.loads(facts["stdout"])
        actual = receipt["actual_gui"]
        assert actual["uid"] == 501 and actual["on_console"] and actual["login_done"]
        assert actual["screen_lock_field"] is not True and actual["keyboard_input_source"] == "com.apple.keylayout.US" and actual["screens"]
        persist()
        # The normal app is never launched before the actual positive control succeeds.
        current = app_action("launch")
        (root / "current-application.json").write_text(json.dumps(current, indent=2) + "\n")
        location = Path(subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()).resolve()
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
        receipt["criteria"]["actual_export_save_and_cancel"] = ui_phase("export", "testNormalExportSaveAndCancel", "ExportPanelTests")
        receipt["actual_outputs"] = validate_outputs(root, receipt, command)
        receipt["criteria"]["actual_html_and_pdf_outputs"] = True
        inspection = app_action("inspect", current)
        assert inspection["pid"] == current["pid"] and inspection["executable"] == current["executable"]
        checked = command("source-and-build-verification-after", ["python3", ".github/scripts/prepare-ordinary-export-acceptance.py", root, "--verify"])
        receipt["criteria"]["unchanged_product_and_source"] = checked["returncode"] == 0
        assert checked["returncode"] == 0
        ending = app_action("terminate", current)
        receipt["criteria"]["normal_identity_bound_quit"] = ending["terminated"]
        assert ending["terminated"]
        current = None
        final = command("source-and-build-verification-after-normal-quit", ["python3", ".github/scripts/prepare-ordinary-export-acceptance.py", root, "--verify"])
        receipt["criteria"]["unchanged_after_normal_quit"] = final["returncode"] == 0
        assert final["returncode"] == 0
    except Exception as error:
        receipt["errors"].append({"type": type(error).__name__, "message": str(error)[:4096]})
    finally:
        if current is not None:
            try:
                app_action("inspect", current)
                app_action("cleanup", current)
            except Exception as error:
                receipt.setdefault("cleanup_errors", []).append(str(error)[:4096])
        receipt["passed"] = (not receipt["errors"] and len(receipt["criteria"]) == 7 and all(receipt["criteria"].values()))
        persist()
    assert receipt["passed"], receipt["errors"]


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Bind actual native app execution to the checkout inputs and configuration."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("configuration", choices=["Debug", "Release"])
parser.add_argument("--verify", action="store_true")
parser.add_argument("--require-result", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
paths = subprocess.check_output([
    "git", "ls-files", "-z", "MacDown2", ".github/scripts/verify-shared-app-probe.py",
    ".github/workflows/shared-math-app-integration.yml", ".github/scripts/run-owned-app-tests.py", ".github/scripts/test-run-owned-app-tests.py",
], cwd=repo).decode().split("\0")
digests = {name: hashlib.sha256((repo / name).read_bytes()).hexdigest() for name in paths if name}
lock = repo / "MacDown2/Packages/MacDownKit/Package.resolved"
pins = json.loads(lock.read_text())["pins"]
receipt = {
    "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "configuration": args.configuration,
    "testability": True,
    "additional_compilation_condition": "RELEASE_PREVIEW_PROBE",
    "source_sha256": digests,
    "pins": pins,
    "scope": "Actual application/test execution; separate from owner observation and signed-artifact acceptance",
}
path = args.output / "receipt.json"
if args.verify:
    if json.loads(path.read_text()) != receipt:
        raise SystemExit("Actual native app source, configuration or immutable pins changed")
    if args.require_result:
        log = re.sub(r"\x1b\[[0-9;]*m", "", (args.output / "probe.log").read_text())
        for suite in ["SharedMathActivationTests", "MathPreviewLiveSourceTests", "MathPreviewNavigationTests",
                      "MathPreviewRecoveryTests", "HeadingPreviewSessionTests", "HeadingPreviewNavigationTests",
                      "HeadingPreviewAppTests", "HeadingExportActivationTests"]:
            if not re.search(r"Suite " + re.escape(suite) + r" passed", log):
                raise SystemExit(suite + " did not execute successfully")
        if not re.search(r"Test run with 28 tests in 8 suites passed", log):
            raise SystemExit("The complete selected actual app controls did not pass")
        if "TOC-PHASE configuration=" + args.configuration not in log:
            raise SystemExit("The production export phase measurement did not execute in this configuration")
    print("Exact actual-app inputs, configuration, pins and requested execution verified")
else:
    args.output.mkdir(parents=True, exist_ok=True)
    with path.open("x") as output:
        json.dump(receipt, output, indent=2)
        output.write("\n")
    print("Recorded actual-app source and immutable pins; execution is still pending")

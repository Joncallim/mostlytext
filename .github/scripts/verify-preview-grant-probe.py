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
    "git", "ls-files", "-z", "MacDown2", ".github/scripts/verify-preview-grant-probe.py",
    ".github/workflows/preview-grant-probe.yml", ".github/scripts/check-preview-parsed-frame.py", ".github/scripts/test-preview-grant-tripwire.py", ".github/scripts/run-preview-grant-probe.py", ".github/scripts/run-owned-app-tests.py", ".github/scripts/test-run-owned-app-tests.py",
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
    "scope": "Inactive three-consumer qualification; separate from production activation, owner observation and signed-artifact acceptance",
}
path = args.output / "receipt.json"
if args.verify:
    if json.loads(path.read_text()) != receipt:
        raise SystemExit("Actual native app source, configuration or immutable pins changed")
    if args.require_result:
        log = re.sub(r"\x1b\[[0-9;]*m", "", (args.output / "probe.log").read_text())
        suites = ["Preview directory grant lifetime", "Preview resource admission", "Preview window resource ownership",
                  "Immutable bounded HTML scheme delivery", "Secured HTML native routing", "Secured Markdown mounted attachment",
                  "Secured Preview ImageIO admission", "Secured Preview observed network denial",
                  "Secured Markdown stable viewport",
                  "Preview image decoded-output admission", "Pinned Textual image interception"]
        if args.configuration == "Release":
            suites.append("Preview Release resource probe")
        for suite in suites:
            if not re.search(r'Suite "' + re.escape(suite) + r'" passed' , log):
                raise SystemExit(suite + " did not execute successfully")
        count = 34 if args.configuration == "Release" else 33
        if not re.search(r"Test run with " + str(count) + r" tests in " + str(len(suites)) + r" suites passed", log):
            raise SystemExit("Every selected consumer test must finish; partial restarts are not accepted")
        if "PREVIEW_NETWORK_CONTROL live=true loaded=true deniedRequests=0" not in log:
            raise SystemExit("Independent live listener and actual WebKit containment did not execute")
        if args.configuration == "Release" and "PREVIEW_RELEASE_PROBE sourceBytes=4194304" not in log:
            raise SystemExit("Optimized maximum-source phase observation did not execute")
        mutation = json.loads((args.output / "parsed-frame-results.json").read_text())
        expected = ["revision-mutant", "revision-restored", "viewport-mutant", "viewport-restored"]
        if [row["phase"] for row in mutation] != expected:
            raise SystemExit("Actual revision/viewport mutation/restoration proof is incomplete")
        for mutant, restored in [(mutation[0], mutation[1]), (mutation[2], mutation[3])]:
            if mutant["returncode"] == 0 or restored["returncode"] != 0:
                raise SystemExit("Actual native counterfactual or restored control has the wrong result")
            if mutant["app_sha256"] == restored["app_sha256"]:
                raise SystemExit("The actual application did not change for a counterfactual")
            if restored["source_sha256"] != receipt["source_sha256"]["MacDown2/MacDown2/SecuredMarkdownResourceHost.swift"]:
                raise SystemExit("The final tested host source was not restored exactly")
    print("Exact actual-app inputs, configuration, pins and requested execution verified")
else:
    args.output.mkdir(parents=True, exist_ok=True)
    with path.open("x") as output:
        json.dump(receipt, output, indent=2)
        output.write("\n")
    print("Recorded actual-app source and immutable pins; execution is still pending")

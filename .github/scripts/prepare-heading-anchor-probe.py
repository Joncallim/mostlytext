#!/usr/bin/env python3
"""Prepare/verify exact heading tests against the checkout's actual package product."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--verify", action="store_true")
parser.add_argument("--require-result", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
package = repo / "MacDown2/Packages/MacDownKit"
test = package / "Tests/ExportServiceTests/HeadingAnchorPreparationTests.swift"
target = args.output / "Tests/HeadingAnchorProbe/HeadingAnchorPreparationTests.swift"
canonical = json.loads((package / "Package.resolved").read_text())
pins = {p["identity"]: (p["location"], p["state"]["revision"]) for p in canonical["pins"]}
source_digests = {
    str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted((package / "Sources").rglob("*.swift"))
}
source_digests[str(test.relative_to(repo))] = hashlib.sha256(test.read_bytes()).hexdigest()
if args.verify:
    receipt = json.loads((args.output / "receipt.json").read_text())
    checkout = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    if receipt["checkout"] != checkout:
        raise SystemExit("Heading probe checkout identity changed")
    actual = json.loads((args.output / "Package.resolved").read_text())
    resolved = {p["identity"]: (p["location"], p["state"]["revision"]) for p in actual["pins"]}
    if resolved != pins or receipt["source_sha256"] != source_digests or target.read_bytes() != test.read_bytes():
        raise SystemExit("Heading probe inputs or immutable dependency owners/revisions changed")
    if args.require_result:
        log = re.sub(r"\x1b\[[0-9;]*m", "", (args.output / "probe.log").read_text())
        if not re.search(r"Test run with 12 tests in 1 suite passed", log):
            raise SystemExit("The twelve actual heading preparation controls did not pass")
    print("Exact actual-package heading tests, source inventory and all immutable pins verified")
else:
    args.output.mkdir(parents=True, exist_ok=False)
    target.parent.mkdir(parents=True)
    shutil.copyfile(test, target)
    manifest = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HeadingAnchorProbe", platforms: [.macOS(.v26)], dependencies: [
    .package(path: PACKAGE_PATH)
], targets: [
    .testTarget(name: "HeadingAnchorProbe", dependencies: [
        .product(name: "ExportService", package: "MacDownKit"),
        .product(name: "MarkdownEngine", package: "MacDownKit")
    ])
])
'''.replace("PACKAGE_PATH", json.dumps(str(package)))
    (args.output / "Package.swift").write_text(manifest)
    (args.output / "Package.resolved").write_text(json.dumps({"version": 2, "pins": canonical["pins"]}, indent=2) + "\n")
    receipt = {
        "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
        "source_sha256": source_digests,
        "pins": pins,
        "scope": "Actual ExportService product and exact copied test; preparation is not execution or native acceptance",
    }
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Prepared exact tests against the actual checkout package; no source adaptation")

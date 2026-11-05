#!/usr/bin/env python3
"""Prepare or verify the exact hosted math accessibility probe and its immutable pins."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--verify", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
source = repo / "MacDown2/Packages/MacDownKit/Tests/PreviewTests/SourceMathAccessibilityProbeTests.swift"
lock = json.loads((repo / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())
identities = {"textual", "swiftui-math", "swift-concurrency-extras"}
pins = [pin for pin in lock["pins"] if pin["identity"] in identities]
if {pin["identity"] for pin in pins} != identities or len(pins) != 3:
    raise SystemExit("Exactly three registered immutable probe dependencies are required")
for pin in pins:
    if not pin["location"].startswith("https://github.com/") or not re.fullmatch(r"[0-9a-f]{40}", pin["state"]["revision"]):
        raise SystemExit("Invalid probe dependency owner or immutable revision")
expected = {pin["identity"]: pin["state"]["revision"] for pin in pins}
target = args.output / "Tests/NativeMathAccessibilityProbe/SourceMathAccessibilityProbeTests.swift"
digest = hashlib.sha256(source.read_bytes()).hexdigest()
if args.verify:
    actual = json.loads((args.output / "Package.resolved").read_text())
    resolved = {pin["identity"]: pin["state"]["revision"] for pin in actual["pins"]}
    if resolved != expected or target.read_bytes() != source.read_bytes():
        raise SystemExit("Probe source or resolved dependencies differ from the application")
    print("Exact native probe source and all three application revisions verified")
else:
    args.output.mkdir(parents=True, exist_ok=False)
    target.parent.mkdir(parents=True)
    shutil.copyfile(source, target)
    requirements = ",\n".join(
        "    .package(url: " + json.dumps(pin["location"]) + ", revision: " + json.dumps(pin["state"]["revision"]) + ")"
        for pin in pins
    )
    manifest = """// swift-tools-version: 6.0
import PackageDescription
let package = Package(
  name: "NativeMathAccessibilityProbe",
  platforms: [.macOS("26.0")],
  dependencies: [
""" + requirements + """
  ],
  targets: [.testTarget(name: "NativeMathAccessibilityProbe", dependencies: [
    .product(name: "Textual", package: "textual"),
    .product(name: "SwiftUIMath", package: "swiftui-math"),
    .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
  ])]
)
"""
    (args.output / "Package.swift").write_text(manifest)
    frozen = [{**pin, "state": {"revision": pin["state"]["revision"]}} for pin in pins]
    (args.output / "Package.resolved").write_text(json.dumps({"pins": frozen, "version": 2}, indent=2) + "\n")
    receipt = {"source": str(source.relative_to(repo)), "source_sha256": digest, "revisions": expected,
               "native_execution": "hosted only; preparation does not execute any native code"}
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Copied the exact native probe with three immutable application pins")

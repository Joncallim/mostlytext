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
parser.add_argument("--require-result", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
sources = [repo / "MacDown2/Packages/MacDownKit/Tests/PreviewTests" / name for name in [
    "SourceMathAccessibilityProbeTests.swift", "SourceAttachmentAccessibilityTests.swift",
    "NativeMathProbeHost.swift", "SourceMathPolicyProbeTests.swift",
    "PreviewMathInputTests.swift", "PreviewMathTransportTests.swift", "PreviewMathScalarGeometryTests.swift",
    "PreviewMarkdownSourceMapTests.swift"
]]
preview_sources = [repo / "MacDown2/Packages/MacDownKit/Sources/Preview" / name for name in [
    "PreviewParserBudget.swift", "PreviewMathInput.swift", "PreviewMathMarkupParser.swift", "PreviewMarkdownSourceMap.swift"
]]
sources += [repo / "MacDown2/Packages/MacDownKit/Tests" / path for path in [
    "MathTests/MathImageBudgetTests.swift", "MathRenderingTests/ValidatedMathImageRendererTests.swift",
    "MathRenderingTests/MathRenderingPerformanceTests.swift"
]]
components = {"Preview": preview_sources,
    "Math": [repo / "MacDown2/Packages/MacDownKit/Sources/Math" / name for name in [
        "MathImageBudget.swift", "MathRenderError.swift", "RenderedMathImage.swift", "MathSpan.swift", "ExportMathRenderContext.swift"
    ]],
    "MathRendering": [repo / "MacDown2/Packages/MacDownKit/Sources/MathRendering" / name for name in [
        "MathImageRenderer.swift", "MathImageRenderer+ValidatedBody.swift"
    ]],
    "MathSyntax": [repo / "MacDown2/Packages/MathSyntax/Sources/MathSyntax/MathSourceValues.swift"]
}
lock = json.loads((repo / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())
identities = {"textual", "swiftui-math", "swift-concurrency-extras"}
pins = [pin for pin in lock["pins"] if pin["identity"] in identities]
if {pin["identity"] for pin in pins} != identities or len(pins) != 3:
    raise SystemExit("Exactly three registered immutable probe dependencies are required")
for pin in pins:
    if not pin["location"].startswith("https://github.com/") or not re.fullmatch(r"[0-9a-f]{40}", pin["state"]["revision"]):
        raise SystemExit("Invalid probe dependency owner or immutable revision")
expected = {pin["identity"]: pin["state"]["revision"] for pin in pins}
targets = [args.output / "Tests/NativeMathAccessibilityProbe" / source.name for source in sources]
component_sources = [source for values in components.values() for source in values]
component_targets = [args.output / "Sources" / module / source.name for module, values in components.items() for source in values]
all_sources = sources + component_sources
all_targets = targets + component_targets
digests = {str(source.relative_to(repo)): hashlib.sha256(source.read_bytes()).hexdigest() for source in all_sources}
if args.verify:
    actual = json.loads((args.output / "Package.resolved").read_text())
    resolved = {pin["identity"]: pin["state"]["revision"] for pin in actual["pins"]}
    if resolved != expected or any(target.read_bytes() != source.read_bytes() for source, target in zip(all_sources, all_targets)):
        raise SystemExit("Probe source or resolved dependencies differ from the application")
    if args.require_result:
        log = (args.output / "probe.log").read_text()
        prefix = "MOSTLYTEXT_MATH_AX_PROBE "
        records = [json.loads(line.split(prefix, 1)[1]) for line in log.splitlines() if prefix in line]
        if not records or not records[-1].get("positiveControlsPresent"):
            raise SystemExit("Native probe did not establish its positive controls")
        descriptor_prefix = "MOSTLYTEXT_ATTACHMENT_AX_RESULT "
        descriptors = [json.loads(line.split(descriptor_prefix, 1)[1]) for line in log.splitlines() if descriptor_prefix in line]
        if not descriptors or not all(descriptors[-1].get(key) for key in
                                      ["positiveControlsPresent", "firstOwnElement", "secondOwnElement"]):
            raise SystemExit("The actual inline descriptors were not exposed")
        if "MOSTLYTEXT_ATTACHMENT_AX_ACTIONS 2" not in log:
            raise SystemExit("Both native occurrence actions were not verified")
        for prefix, fields in [
            ("MOSTLYTEXT_MATH_PLACEMENT_PROBE ", ["displayBaseClassified", "displayWrappedClassified"]),
            ("MOSTLYTEXT_MATH_FONT_PROBE ", ["positiveControlsPresent", "fontControlUpdated", "attachmentGeometryUpdated"]),
        ]:
            values = [json.loads(line.split(prefix, 1)[1]) for line in log.splitlines() if prefix in line]
            if not values or not all(values[-1].get(field) for field in fields):
                raise SystemExit("Native math placement/font controls did not pass")
        geometry_prefix = "MOSTLYTEXT_MATH_SCALAR_GEOMETRY "
        geometry = [json.loads(line.split(geometry_prefix, 1)[1]) for line in log.splitlines() if geometry_prefix in line]
        if not geometry or geometry[-1].get("actualOccurrenceCount") != 6 or not all(
            geometry[-1].get(field) for field in ["positiveControlsPresent", "allFramesInsideHost", "distinctFrames"]
        ):
            raise SystemExit("Six scalar-adjacent native occurrences were not verified")
        if not re.search(r"Test run with 37 tests in 10 suites passed", log):
            raise SystemExit("The actual native test did not pass")
        print("Actual native test and positive-control result verified")
    print("Exact native probe source and all three application revisions verified")
else:
    args.output.mkdir(parents=True, exist_ok=False)
    for target in all_targets:
        target.parent.mkdir(parents=True, exist_ok=True)
    for source, target in zip(all_sources, all_targets):
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
  targets: [
  .target(name: "Preview", dependencies: [.product(name: "Textual", package: "textual")]),
  .target(name: "Math"),
  .target(name: "MathSyntax"),
  .target(name: "MathRendering", dependencies: ["Math", "MathSyntax", .product(name: "SwiftUIMath", package: "swiftui-math")]),
  .testTarget(name: "NativeMathAccessibilityProbe", dependencies: [
    "Preview", "Math", "MathSyntax", "MathRendering", .product(name: "Textual", package: "textual"),
    .product(name: "SwiftUIMath", package: "swiftui-math"),
    .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
  ])]
)
"""
    (args.output / "Package.swift").write_text(manifest)
    frozen = [{**pin, "state": {"revision": pin["state"]["revision"]}} for pin in pins]
    (args.output / "Package.resolved").write_text(json.dumps({"pins": frozen, "version": 2}, indent=2) + "\n")
    receipt = {"source_sha256": digests, "revisions": expected,
               "native_execution": "hosted only; preparation does not execute any native code"}
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Copied the exact native probe with three immutable application pins")

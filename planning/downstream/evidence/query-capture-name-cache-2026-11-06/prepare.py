#!/usr/bin/env python3
"""Prepare owned, exact-revision Foundation/C probes; never execute them."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("repository", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
repo, output = args.repository.resolve(), args.output.resolve()
if output.exists() or output == repo or repo in output.parents:
    parser.error("Use a new owned output directory outside the source checkout")
evidence = Path(__file__).resolve().parent
fixture = repo / "MacDown2/Packages/MacDownKit/Tests/HighlightingTests/Fixtures.swift"
if fixture.read_bytes() != (evidence / "probe-fixture.swift").read_bytes():
    parser.error("The production fixture changed; review and rebaseline explicitly")
canonical = json.loads((repo / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())["pins"]
pins = {p["identity"]: p for p in canonical}
if pins["tree-sitter"]["state"]["revision"] != "5ce80b6f0e29096a5f06826a3ba610c4e89bc255":
    parser.error("The runtime changed; review and rebaseline explicitly")
output.mkdir(parents=True)
records = []
for phase, revision, name in [
    ("baseline", "0beea992c4246f93a122de846c8611c9be19aeb7", "probe"),
    ("candidate", "f2163a8bc5d0f1ce76b4cead48ce0f3ade4aa9f3", "candidate-probe"),
]:
    original = repo / "MacDown2/Packages/TreeSitterMarkdown"
    grammar = output / (phase + "-source") / "TreeSitterMarkdown"
    shutil.copytree(original, grammar, ignore=shutil.ignore_patterns(".build", ".swiftpm", "Package.resolved"))
    source_hashes = {}
    for source in original.rglob("*"):
        if not source.is_file() or any(p in {".build", ".swiftpm"} for p in source.relative_to(original).parts):
            continue
        if source.name == "Package.resolved":
            continue
        copied = grammar / source.relative_to(original)
        if copied.read_bytes() != source.read_bytes():
            raise SystemExit("Owned grammar copy differs: " + str(source))
        source_hashes[str(source.relative_to(original))] = hashlib.sha256(source.read_bytes()).hexdigest()
    package_manifest = grammar / "Package.swift"
    text, count = re.subn(r'revision: "[0-9a-f]{40}"', 'revision: "' + revision + '"', package_manifest.read_text())
    if count != 1:
        raise SystemExit("Expected the single reviewed Markdown dependency requirement")
    package_manifest.write_text(text)
    package = output / name
    target = package / "Sources/ParserQueryProfile"
    target.mkdir(parents=True)
    shutil.copyfile(evidence / "probe-main.swift", target / "main.swift")
    shutil.copyfile(evidence / "probe-fixture.swift", target / "Fixtures.swift")
    manifest = ('// swift-tools-version: 6.2\nimport PackageDescription\n'
                'let package = Package(name: "ParserQueryProfile", platforms: [.macOS(.v26)], dependencies: [\n'
                '.package(url: "https://github.com/Joncallim/SwiftTreeSitter", revision: ' + json.dumps(revision) + '),\n'
                '.package(path: ' + json.dumps(str(grammar)) + ')\n], targets: [\n'
                '.executableTarget(name: "ParserQueryProfile", dependencies: [\n'
                '.product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),\n'
                '.product(name: "TreeSitterMarkdown", package: "TreeSitterMarkdown")])])\n')
    (package / "Package.swift").write_text(manifest)
    selected = [dict(pins[name]) for name in ["swifttreesitter", "tree-sitter"]]
    selected[0]["state"] = {"revision": revision}
    (package / "Package.resolved").write_text(json.dumps({"version": 2, "pins": selected}, indent=2) + "\n")
    records.append({"phase": phase, "revision": revision, "original_grammar_sha256": source_hashes,
                    "phase_grammar_manifest_sha256": hashlib.sha256(text.encode()).hexdigest(),
                    "probe_manifest_sha256": hashlib.sha256(manifest.encode()).hexdigest(), "pins": selected})
shutil.copyfile(evidence / "measurement.py", output / "measurement.py")
(output / "preparation.json").write_text(json.dumps(records, indent=2) + "\n")
print("Prepared both owned exact-revision probes; no native application or test helper executed")

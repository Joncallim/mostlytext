#!/usr/bin/env python3
"""Check source inventory and retained behavior IDs; never infer native results."""
import argparse
import hashlib
import json
from pathlib import Path
import re

FROZEN_IDS_SHA256 = "08236911cd3661b461bd984d99c11f024ff21b4719fad68d1228c5cc7217d57d"
ADDITIONAL = {"actual-pdf-menu-save-panel", "finder-quicklook-complete-lifecycle", "theme-accessibility-and-localized-layout",
              "complete-e22-editing-performance", "protected-owner-runtime-denial", "exact-signed-release-public-ui"}


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise ValueError("Duplicate manifest key: " + key)
        result[key] = value
    return result


def validate(root, manifest):
    expected_keys = {"schemaVersion", "sourceBaseline", "scope", "originalRequiredIDs", "sources", "cases", "replacements", "additionalRequiredBehaviors"}
    if set(manifest) != expected_keys or type(manifest["schemaVersion"]) is not int or manifest["schemaVersion"] != 1:
        raise ValueError("Unsupported source inventory schema or result-like extra fields")
    frozen = manifest["originalRequiredIDs"]
    if frozen != sorted(set(frozen)) or hashlib.sha256(("\n".join(frozen) + "\n").encode()).hexdigest() != FROZEN_IDS_SHA256:
        raise ValueError("Original required behavior IDs changed")
    actual_sources = {}
    actual_cases = {}
    for path in sorted((root / "MacDown2/MacDown2UITests").rglob("*.swift")):
        if path.is_symlink(): raise ValueError("Symlinked UI source")
        raw = path.read_bytes()
        name = str(path.relative_to(root))
        actual_sources[name] = hashlib.sha256(raw).hexdigest()
        text = raw.decode("utf-8")
        classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase", text)
        methods = re.findall(r"^\s+func\s+(test\w+)\s*\(", text, re.M)
        if methods and len(classes) != 1: raise ValueError("Ambiguous source declaration inventory: " + name)
        for method in methods:
            case = "MacDown2UITests/" + classes[0] + "/" + method
            if case in actual_cases: raise ValueError("Duplicate source case")
            actual_cases[case] = name
    declared = {}
    for case in manifest["cases"]:
        if set(case) != {"id", "source", "area"} or not case["area"] or case["id"] in declared:
            raise ValueError("Malformed/duplicate source case or result-like fields")
        declared[case["id"]] = case["source"]
    if declared != actual_cases:
        raise ValueError("Source case inventory differs; a removal, rename or addition requires reconciliation")
    if actual_sources != manifest["sources"]:
        raise ValueError("Source bytes changed; refresh the explicit source binding after review")
    replacements = {}
    targets = set()
    for replacement in manifest["replacements"]:
        if set(replacement) != {"original", "replacement", "reason", "evidenceReference"}:
            raise ValueError("A replacement needs a reason and traceable evidence")
        old, new = replacement["original"], replacement["replacement"]
        if old not in frozen or old in actual_cases or new not in actual_cases or old in replacements or new in targets:
            raise ValueError("Invalid/duplicate behavior replacement")
        if not replacement["reason"].strip() or not replacement["evidenceReference"].strip():
            raise ValueError("Unexplained behavior replacement")
        replacements[old] = new
        targets.add(new)
    if set(frozen) - set(actual_cases) != set(replacements):
        raise ValueError("An original required behavior was removed without its traceable replacement")
    other = manifest["additionalRequiredBehaviors"]
    if len(other) != len(ADDITIONAL) or {c.get("id") for c in other} != ADDITIONAL:
        raise ValueError("Absent-source critical journeys cannot disappear from the contract")
    for item in other:
        if set(item) != {"id", "ownerIssue"} or type(item["ownerIssue"]) is not int or item["ownerIssue"] <= 0:
            raise ValueError("Invalid additional required behavior")
    if not re.fullmatch(r"[0-9a-f]{40}", manifest["sourceBaseline"]):
        raise ValueError("Invalid source baseline")
    return {"declared_source_cases": len(actual_cases), "source_files": len(actual_sources), "retained_original_behavior_ids": len(frozen),
            "traceable_replacements": len(replacements), "additional_required_journeys": len(other),
            "scope": "Source declarations only; runtime discovery, execution, results and final critical acceptance remain separate."}


def main():
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=repo)
    parser.add_argument("--manifest", type=Path, default=repo / "planning/downstream/native-ui-required-cases.json")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(), object_pairs_hook=reject_duplicates)
    print(json.dumps(validate(args.source_root.resolve(), manifest), indent=2))


if __name__ == "__main__":
    main()

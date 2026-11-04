#!/usr/bin/env python3
"""Verify captured link-stage inputs without executing a compiler or renderer."""

import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_graphviz_link as link
import verify_graphviz_rebuild as original

PACKET = "compliance/evidence/graphviz-link-inputs"
RECEIPT_SHA256 = "520b112060cd872b775da8b41d5ae2775b6d590128c9b3cd6110049ad1a57877"


def expected_inputs(root=link.ROOT):
    original.verify(root)
    prior = json.loads((root / original.PACKET / "result.json").read_text())["inputs"]
    raw = (root / original.PACKET / "upstream-Dockerfile").read_bytes()
    context = dict(prior["context"])
    context["Dockerfile"] = link.backend.record(link.recipe(raw, root))
    return {"schema": 1, "backend_preparation": prior, "diagnostic_context": context,
            "tool_sha256": link.backend.sha((root / "compliance/tools/capture_graphviz_link.py").read_bytes())}


def validate(result, raw_map, raw_why, root=link.ROOT):
    require = link.backend.require
    inputs = expected_inputs(root)
    require(result.get("schema") == 1 and result.get("inputs") == inputs, "Link input/recipe/tool binding differs")
    require(result.get("backend_equal") is True and result.get("built_backend") == inputs["backend_preparation"]["expected_backend"],
            "Complete diagnostic backend differs")
    require(result.get("scope") == link.SCOPE, "Link evidence scope differs")
    require(result.get("sidecars") == {"backend.map": link.backend.record(raw_map), "why-extract.tsv": link.backend.record(raw_why)},
            "Raw diagnostic identity differs")
    require(result.get("index") == link.summarize(raw_map, raw_why), "Link index differs from raw diagnostics")
    hosted = result.get("hosted", {})
    require(isinstance(hosted, dict) and set(hosted) == {"source_head", "run_id", "url"}, "Missing hosted identity")
    require(re.fullmatch(r"[0-9a-f]{40}", hosted["source_head"]) and re.fullmatch(r"[0-9]+", hosted["run_id"]), "Invalid hosted identity")
    require(hosted["url"] == "https://github.com/Joncallim/mostlytext/actions/runs/" + hosted["run_id"], "Hosted URL differs")
    require(set(result) == {"schema", "inputs", "backend_equal", "built_backend", "scope", "sidecars", "index", "hosted"},
            "Unexpected link receipt fields")
    index = result["index"]
    return {"status": "passed", "backend": result["built_backend"], "hosted": hosted, "scope": result["scope"],
            "map_rows": index["map_rows"], "extraction_rows": len(index["extraction_rows"]),
            "mapped_archive_members": len(index["map_archive_members"]),
            "extracted_archive_members": len(index["extracted_archive_members"]),
            "unparsed_extracted_inputs": len(index["unparsed_extracted_inputs"])}


def verify(root=link.ROOT):
    folder = root / PACKET
    result = link.backend.read_regular(folder / "result.json", link.LIMIT)
    link.backend.require(RECEIPT_SHA256 is not None and link.backend.sha(result) == RECEIPT_SHA256, "Captured link receipt differs")
    return validate(json.loads(result), link.backend.read_regular(folder / "backend.map", link.LIMIT),
                    link.backend.read_regular(folder / "why-extract.tsv", link.LIMIT), root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=link.ROOT)
    args = parser.parse_args()
    print(json.dumps(verify(args.root), indent=2, sort_keys=True))

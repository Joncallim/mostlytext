#!/usr/bin/env python3
"""Verify a captured backend rebuild receipt offline; not a rights clearance."""

import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebuild_graphviz_backend as rebuild
import verify_viz_image

PACKET = "compliance/evidence/graphviz-backend-reproduction"
# Filled only after the hosted result and raw run logs have been inspected.
RECEIPT_SHA256 = "d2a79b699ef1e82e2d27eb658ca1af56c03a9a4b852d7b24714d412c9b536c12"


def validate(result, root=rebuild.ROOT):
    require = rebuild.require
    source = rebuild.audit(root)
    folder = root / PACKET
    original = rebuild.read_regular(folder / "upstream-Dockerfile", rebuild.MAX_MEMBER)
    recipe = rebuild.derive_recipe(original, root)
    license_bytes = rebuild.read_regular(folder / "UPSTREAM-LICENSE.txt", rebuild.MAX_MEMBER)
    require(rebuild.sha(license_bytes) == source["build_source_sha256"]["LICENSE"], "Upstream licence differs")
    context = {"Dockerfile": rebuild.record(recipe)}
    for name in ("expat-2.8.4.tar.gz", "graphviz-16.0.0.tar.gz"):
        context[name] = source["archives"][name]
    for name, size in (("viz.c", 5274), ("pre.js", 112)):
        context[name] = {"bytes": size, "sha256": source["build_source_sha256"]["packages/viz/backend/" + name]}
    backend = {"bytes": rebuild.BACKEND_BYTES, "sha256": source["backend_sha256"]}
    expected = {
        "schema": 1, "image": rebuild.IMAGE, "viz_revision": rebuild.REVISION,
        "archives": source["archives"], "original_recipe": rebuild.record(original),
        "context": context, "expected_backend": backend,
        "shipped_bundle_sha256": source["shipped_bundle_sha256"],
        "tool_sha256": rebuild.sha((root / "compliance/tools/rebuild_graphviz_backend.py").read_bytes()),
    }
    require(result.get("schema") == 1 and result.get("inputs") == expected, "Rebuild input/recipe/tool binding differs")
    require(result.get("backend_equal") is True and result.get("built_backend") == backend, "Complete backend differs")
    require(result.get("scope") == "complete npm backend only; not full wrapper rebuild, historical attestation or rights clearance", "Rebuild scope differs")
    hosted = result.get("hosted", {})
    require(set(hosted) == {"source_head", "run_id", "url"}, "Missing hosted identity")
    require(re.fullmatch(r"[0-9a-f]{40}", hosted["source_head"]) and re.fullmatch(r"[0-9]+", hosted["run_id"]), "Invalid hosted identity")
    require(hosted["url"] == "https://github.com/Joncallim/mostlytext/actions/runs/" + hosted["run_id"], "Hosted URL differs")
    require(set(result) == {"schema", "inputs", "built_backend", "backend_equal", "scope", "hosted"}, "Unexpected receipt fields")
    resource = root / "MacDown2/Packages/MacDownKit/Sources/GraphvizRendering/Resources/viz-global.js"
    require(rebuild.sha(resource.read_bytes()) == expected["shipped_bundle_sha256"], "Shipped Graphviz bundle differs")
    verify_viz_image.verify_installed(root)
    return {"status": "passed", "backend": backend, "hosted": hosted, "scope": result["scope"]}


def verify(root=rebuild.ROOT):
    data = rebuild.read_regular(root / PACKET / "result.json", rebuild.MAX_MEMBER)
    rebuild.require(RECEIPT_SHA256 is not None and rebuild.sha(data) == RECEIPT_SHA256, "Captured rebuild receipt differs")
    return validate(json.loads(data), root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=rebuild.ROOT)
    args = parser.parse_args()
    print(json.dumps(verify(args.root), indent=2, sort_keys=True))

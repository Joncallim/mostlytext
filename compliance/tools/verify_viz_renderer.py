#!/usr/bin/env python3
"""Verify complete Viz.js generated-file correspondence without executing it."""

import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebuild_viz_renderer as renderer
import verify_graphviz_rebuild

RECEIPT_SHA256 = "86dba0eb97b420ba7792da52c48c57580e2730654c94a520d19d004eac50a762"
DEPENDENCIES_SHA256 = "a6acbcb96c8dbd765799f942677966e41a07726d22fa27cc890b2bb1f18cc43a"
OUTPUTS = {
    "backend.js": {"bytes": 1173021, "sha256": "d2d18f488ffbf12fd3ae68d3899d6911051b9bfc3b4240eebe9883ca17d58903"},
    "metadata.js": {"bytes": 390, "sha256": "93aaf62515bbabe886fa45c8bb69fe123101ff348bdf125c0605d1bfae448560"},
    "viz-global.js": {"bytes": 1324675, "sha256": "c857641af952c8f82ac7243917f8563959046e5cfc44d7e84eff9a2b470f5eab"},
    "viz.cjs": {"bytes": 1184659, "sha256": "3a3e781ad124732227594c3940246a2e282f745eaacc584eafdbcd359aea92c0"},
    "viz.js": {"bytes": 1184246, "sha256": "fef725087058053ea3fe002159d456b49c92a1d38f16bc6bbae4874fc9f3c33f"},
}


def dependency_receipt(root=renderer.ROOT):
    backend = renderer.backend
    folder = root / renderer.PACKET
    lock = backend.read_regular(folder / "package-lock.json", backend.MAX_MEMBER)
    plan = renderer.dependency_plan(lock, root)
    data = backend.read_regular(folder / "dependencies.json", backend.MAX_MEMBER)
    backend.require(backend.sha(data) == DEPENDENCIES_SHA256, "Dependency receipt differs")
    value = json.loads(data)
    objects = value.get("objects", {})
    backend.require(set(value) == {"objects", "object_count", "total_bytes"}
                    and set(objects) == set(plan) and value["object_count"] == len(plan), "Dependency receipt membership differs")
    total = 0
    for name, expected in plan.items():
        item = objects[name]
        backend.require(set(item) == {"integrity", "url", "bytes", "sha256"}, "Dependency fields differ")
        backend.require({k: item[k] for k in expected} == expected, "Dependency lock binding differs")
        backend.require(type(item["bytes"]) is int and 0 < item["bytes"] <= renderer.MAX_PACKAGE
                        and re.fullmatch(r"[0-9a-f]{64}", item["sha256"]), "Dependency size/hash differs")
        total += item["bytes"]
    backend.require(total == value["total_bytes"] and total <= renderer.MAX_PACKAGES_TOTAL, "Dependency total bound differs")
    return value


def expected_inputs(root=renderer.ROOT):
    backend = renderer.backend
    verify_graphviz_rebuild.verify(root)
    prior = json.loads((root / verify_graphviz_rebuild.PACKET / "result.json").read_text())["inputs"]
    node = renderer.node_reference(root)
    original = (root / verify_graphviz_rebuild.PACKET / "upstream-Dockerfile").read_bytes()
    context = dict(prior["context"])
    context["Dockerfile"] = backend.record(renderer.recipe(original, root))
    context[node["archive"]] = {"bytes": node["bytes"], "sha256": node["sha256"]}
    context["viz-source-99da545.tar.gz"] = prior["archives"]["viz-source-99da545.tar.gz"]
    lock_sha = backend.audit(root)["build_source_sha256"]["package-lock.json"]
    return {"schema": 1, "backend_preparation": prior, "node": node,
            "lock": {"bytes": 294054, "sha256": lock_sha, "resolved_registry_inputs": 546},
            "context": context, "dependencies": dependency_receipt(root), "expected_outputs": OUTPUTS,
            "tool_sha256": backend.sha((root / "compliance/tools/rebuild_viz_renderer.py").read_bytes())}


def validate(result, root=renderer.ROOT):
    require = renderer.backend.require
    require(result.get("schema") == 1 and result.get("inputs") == expected_inputs(root), "Renderer input/source/recipe/tool binding differs")
    require(result.get("all_outputs_equal") is True and result.get("actual_outputs") == OUTPUTS, "Complete generated runtime differs")
    require(result.get("scope") == renderer.SCOPE, "Renderer scope differs")
    versions = result.get("measured_versions", {})
    require(set(versions) == {"node", "npm"} and versions["node"] == "v24.19.0"
            and re.fullmatch(r"\d+\.\d+\.\d+", versions["npm"]), "Measured versions differ")
    hosted = result.get("hosted", {})
    require(set(hosted) == {"source_head", "run_id", "url"}, "Missing hosted identity")
    require(re.fullmatch(r"[0-9a-f]{40}", hosted["source_head"]) and re.fullmatch(r"[0-9]+", hosted["run_id"]), "Invalid hosted identity")
    require(hosted["url"] == "https://github.com/Joncallim/mostlytext/actions/runs/" + hosted["run_id"], "Hosted URL differs")
    require(set(result) == {"schema", "inputs", "actual_outputs", "all_outputs_equal", "scope", "measured_versions", "hosted"}, "Unexpected renderer receipt fields")
    resource = root / "MacDown2/Packages/MacDownKit/Sources/GraphvizRendering/Resources/viz-global.js"
    require(renderer.backend.record(resource.read_bytes()) == OUTPUTS["viz-global.js"], "Shipped renderer differs")
    return {"status": "passed", "generated_files": 5, "shipped_renderer": OUTPUTS["viz-global.js"],
            "measured_versions": versions, "hosted": hosted, "scope": result["scope"]}


def verify(root=renderer.ROOT):
    data = renderer.backend.read_regular(root / renderer.PACKET / "result.json", renderer.backend.MAX_MEMBER)
    renderer.backend.require(RECEIPT_SHA256 is not None and renderer.backend.sha(data) == RECEIPT_SHA256, "Captured renderer receipt differs")
    return validate(json.loads(data), root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=renderer.ROOT)
    parser.add_argument("--packages", type=Path, help="Optional retained raw tarball cache replay; no download or execution")
    args = parser.parse_args()
    if args.packages:
        lock = (args.root / renderer.PACKET / "package-lock.json").read_bytes()
        actual = renderer.checked_packages(renderer.dependency_plan(lock, args.root), args.packages)
        renderer.backend.require(actual == dependency_receipt(args.root), "Raw dependency cache differs")
    print(json.dumps(verify(args.root), indent=2, sort_keys=True))

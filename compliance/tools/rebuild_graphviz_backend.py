#!/usr/bin/env python3
"""Prepare pinned inputs and compare an isolated hosted Graphviz backend build.

This program never executes upstream code or invokes Docker. Only the separate
hosted workflow executes the prepared recipe, with network disabled for RUN.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
IMAGE = "emscripten/emsdk@sha256:c2ac84c26ee40ae2f2c5a15bd3f9e608d1959e1b37413fa7f08138046a188dc5"
REVISION = "99da545270e6e7b127a5c7ba65974b8a604a6358"
BACKEND_BYTES = 1173021
MAX_MEMBER = 2 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def record(data):
    return {"bytes": len(data), "sha256": sha(data)}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def audit(root):
    return json.loads((root / "compliance/evidence/viz-js-3.30.0/source-audit.json").read_text())


def read_regular(path, limit):
    require(not path.is_symlink() and path.is_file(), f"Not a regular file: {path}")
    with path.open("rb") as source:
        data = source.read(limit + 1)
    require(len(data) <= limit, f"Oversized input: {path}")
    return data


def selected_member(archive, name):
    require(not name.startswith("/") and ".." not in name.split("/"), "Unsafe selected path")
    matches = [entry for entry in archive.getmembers() if entry.name == name]
    require(len(matches) == 1, f"Missing/duplicate selected member: {name}")
    entry = matches[0]
    require(entry.isfile() and 0 <= entry.size <= MAX_MEMBER, f"Non-file/oversized member: {name}")
    with archive.extractfile(entry) as stream:
        data = stream.read(MAX_MEMBER + 1)
    require(len(data) == entry.size, f"Short/oversized member: {name}")
    return data


def derive_recipe(original, root=ROOT):
    expected = audit(root)["build_source_sha256"]["packages/viz/backend/Dockerfile"]
    require(sha(original) == expected, "Unexpected original Dockerfile")
    require(original.count(b"FROM emscripten/emsdk:5.0.7 AS ") == 2, "Expected two fresh compiler stages")
    replacements = {
        b"FROM emscripten/emsdk:5.0.7 AS ": ("FROM " + IMAGE + " AS ").encode(),
        b'ADD "https://github.com/libexpat/libexpat/releases/download/R_2_8_4/expat-2.8.4.tar.gz" ./expat.tar.gz':
            b"COPY expat-2.8.4.tar.gz ./expat.tar.gz",
        b'ADD "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/16.0.0/graphviz-16.0.0.tar.gz" ./graphviz.tar.gz':
            b"COPY graphviz-16.0.0.tar.gz ./graphviz.tar.gz",
    }
    recipe = original
    for old, new in replacements.items():
        require(recipe.count(old) == (2 if old.startswith(b"FROM ") else 1), "Unexpected recipe instruction")
        recipe = recipe.replace(old, new)
    return recipe


def new_scratch(path, root):
    require(not path.resolve().is_relative_to(root.resolve()), "Scratch must be outside the checkout")
    path.mkdir(parents=True, exist_ok=False)


def download(inputs, root=ROOT):
    """Explicit network operation; writes only a new owned input directory."""
    expected = audit(root)["archives"]
    downloads = json.loads((root / "compliance/evidence/viz-js-3.30.0/downloads.json").read_text())
    new_scratch(inputs, root)
    for name, identity in expected.items():
        item = next(item for item in downloads if item["name"] == name)
        require(item["sha256"] == identity["sha256"], f"Download identity mismatch: {name}")
        request = urllib.request.Request(item["url"], headers={"User-Agent": "MostlyText-source-reproduction"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read(identity["bytes"] + 1)
        require(record(data) == identity, f"Downloaded archive differs: {name}")
        with (inputs / name).open("xb") as stream:
            stream.write(data)


def descriptor(output, root=ROOT):
    """Recheck every context byte; metadata cannot authorize different inputs."""
    source_audit = audit(root)
    context = output / "context"
    names = {"Dockerfile", "viz.c", "pre.js", "expat-2.8.4.tar.gz", "graphviz-16.0.0.tar.gz"}
    require({p.name for p in context.iterdir()} == names, "Unexpected build context members")
    original = read_regular(output / "upstream-Dockerfile", MAX_MEMBER)
    recipe = derive_recipe(original, root)
    require(read_regular(context / "Dockerfile", MAX_MEMBER) == recipe, "Derived Dockerfile differs")
    records = {}
    for name in sorted(names):
        if name in source_audit["archives"]:
            expected = source_audit["archives"][name]
            data = read_regular(context / name, expected["bytes"])
            require(record(data) == expected, f"Context archive differs: {name}")
        else:
            data = read_regular(context / name, MAX_MEMBER)
            if name != "Dockerfile":
                expected = source_audit["build_source_sha256"]["packages/viz/backend/" + name]
                require(sha(data) == expected, f"Context source differs: {name}")
        records[name] = record(data)
    return {
        "schema": 1,
        "image": IMAGE,
        "viz_revision": REVISION,
        "archives": source_audit["archives"],
        "original_recipe": record(original),
        "context": records,
        "expected_backend": {"bytes": BACKEND_BYTES, "sha256": source_audit["backend_sha256"]},
        "shipped_bundle_sha256": source_audit["shipped_bundle_sha256"],
        "tool_sha256": sha(Path(__file__).read_bytes()),
    }


def prepare(inputs, output, root=ROOT):
    source_audit = audit(root)
    for name, identity in source_audit["archives"].items():
        require(record(read_regular(inputs / name, identity["bytes"])) == identity, f"Archive differs: {name}")
    new_scratch(output, root)
    context = output / "context"
    context.mkdir()
    with tarfile.open(inputs / "viz-source-99da545.tar.gz") as archive:
        prefix = f"viz-js-{REVISION}/packages/viz/backend/"
        original = selected_member(archive, prefix + "Dockerfile")
        (output / "upstream-Dockerfile").write_bytes(original)
        (context / "Dockerfile").write_bytes(derive_recipe(original, root))
        for name in ("viz.c", "pre.js"):
            (context / name).write_bytes(selected_member(archive, prefix + name))
    for name in ("expat-2.8.4.tar.gz", "graphviz-16.0.0.tar.gz"):
        (context / name).write_bytes(read_regular(inputs / name, source_audit["archives"][name]["bytes"]))
    with tarfile.open(inputs / "viz-3.30.0.tgz") as archive:
        backend = selected_member(archive, "package/lib/backend.js")
    require(record(backend) == {"bytes": BACKEND_BYTES, "sha256": source_audit["backend_sha256"]}, "npm backend differs")
    result = descriptor(output, root)
    write_json(output / "prepared.json", result)
    return result


def compare(output, built, root=ROOT):
    expected = descriptor(output, root)
    require(json.loads(read_regular(output / "prepared.json", MAX_MEMBER)) == expected, "Preparation receipt differs")
    data = read_regular(built / "backend.js", MAX_MEMBER)
    result = {
        "schema": 1,
        "inputs": expected,
        "built_backend": record(data),
        "backend_equal": record(data) == expected["expected_backend"],
        "scope": "complete npm backend only; not full wrapper rebuild, historical attestation or rights clearance",
    }
    head = os.environ.get("SOURCE_HEAD", "")
    run = os.environ.get("GITHUB_RUN_ID", "")
    if head or run:
        require(re.fullmatch(r"[0-9a-f]{40}", head) and re.fullmatch(r"[0-9]+", run), "Invalid hosted run identity")
        result["hosted"] = {"source_head": head, "run_id": run,
                            "url": f"https://github.com/Joncallim/mostlytext/actions/runs/{run}"}
    write_json(output / "result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--inputs", type=Path, required=True)
    prep.add_argument("--output", type=Path, required=True)
    prep.add_argument("--download", action="store_true")
    check = sub.add_parser("compare")
    check.add_argument("--output", type=Path, required=True)
    check.add_argument("--built", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        if args.download:
            download(args.inputs)
        result = prepare(args.inputs, args.output)
    else:
        result = compare(args.output, args.built)
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.command == "compare" and not result["backend_equal"]:
        raise SystemExit("Complete rebuilt backend differs; receipt preserved")


if __name__ == "__main__":
    main()

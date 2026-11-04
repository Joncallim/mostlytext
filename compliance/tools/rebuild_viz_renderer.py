#!/usr/bin/env python3
"""Prepare/compare a complete hosted Viz.js build; no upstream execution here."""

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tarfile
from threading import Lock
from urllib.parse import urlsplit
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebuild_graphviz_backend as backend

ROOT = backend.ROOT
PACKET = "compliance/evidence/viz-renderer-reproduction"
GENERATED = {"backend.js": "lib/backend.js", "metadata.js": "lib/metadata.js",
             "viz.js": "dist/viz.js", "viz.cjs": "dist/viz.cjs", "viz-global.js": "dist/viz-global.js"}
SCOPE = "all five generated npm runtime files; not full npm archive, historical attestation or rights clearance"
MAX_PACKAGE = 32 * 1024 * 1024
MAX_PACKAGES_TOTAL = 512 * 1024 * 1024


def node_reference(root=ROOT):
    folder = root / PACKET
    info = json.loads((folder / "node-reference.json").read_text())
    sums = (folder / "SHASUMS256.txt").read_bytes()
    backend.require(backend.sha(sums) == info["checksum_sha256"], "Node checksum list differs")
    backend.require(info["version"] == "24.19.0" and info["archive"] == "node-v24.19.0-linux-x64.tar.xz", "Node reference differs")
    backend.require(info["url"] == "https://nodejs.org/dist/v24.19.0/" + info["archive"], "Node URL differs")
    rows = [l.split() for l in sums.decode().splitlines() if l.split()[-1] == info["archive"]]
    backend.require(len(rows) == 1 and rows[0][0] == info["sha256"], "Node archive not bound to checksum list")
    publisher = backend.read_regular(folder / "npm-publisher.json", backend.MAX_MEMBER)
    downloads = json.loads((root / "compliance/evidence/viz-js-3.30.0/downloads.json").read_text())
    pin = next(x for x in downloads if x["name"] == "npm-viz-3.30.0.json")
    backend.require(backend.record(publisher) == {"bytes": pin["bytes"], "sha256": pin["sha256"]}, "Publisher reference differs")
    backend.require(json.loads(publisher)["_nodeVersion"] == info["version"], "Publisher Node reference differs")
    return info


def check_lock(data, root=ROOT):
    backend.require(backend.sha(data) == backend.audit(root)["build_source_sha256"]["package-lock.json"], "Frozen npm lock differs")
    lock = json.loads(data)
    backend.require(lock["lockfileVersion"] == 3, "Unexpected npm lock format")
    resolved = 0
    for entry in lock["packages"].values():
        if not entry.get("resolved") or entry.get("link"):
            continue
        url = urlsplit(entry["resolved"])
        backend.require(url.scheme == "https" and url.netloc == "registry.npmjs.org" and not url.username and not url.fragment,
                        "Unexpected resolved dependency source")
        backend.require(re.fullmatch(r"sha(?:1|256|384|512)-[A-Za-z0-9+/]+=*", entry.get("integrity", "")), "Missing/invalid dependency integrity")
        resolved += 1
    backend.require(resolved == 546, "Unexpected resolved dependency count")
    return {"bytes": len(data), "sha256": backend.sha(data), "resolved_registry_inputs": resolved}


def lock_bytes(inputs, root=ROOT):
    path = inputs / "viz-source-99da545.tar.gz"
    expected = backend.audit(root)["archives"][path.name]
    backend.require(backend.record(backend.read_regular(path, expected["bytes"])) == expected, "Source archive differs")
    with tarfile.open(path) as archive:
        return backend.selected_member(archive, f"viz-js-{backend.REVISION}/package-lock.json")


def dependency_plan(data, root=ROOT):
    check_lock(data, root)
    objects = {}
    for entry in json.loads(data)["packages"].values():
        if not entry.get("resolved") or entry.get("link"):
            continue
        integrity = entry["integrity"]
        name = backend.sha(integrity.encode()) + ".tgz"
        item = {"integrity": integrity, "url": entry["resolved"]}
        if name in objects:
            backend.require(objects[name]["integrity"] == integrity, "Dependency object collision")
            item["url"] = min(item["url"], objects[name]["url"])
        objects[name] = item
    return dict(sorted(objects.items()))


def check_integrity(data, integrity):
    backend.require(len(data) <= MAX_PACKAGE, "Oversized dependency object")
    algorithm, encoded = integrity.split("-", 1)
    backend.require(algorithm in {"sha1", "sha256", "sha384", "sha512"}, "Unsupported dependency integrity")
    expected = base64.b64decode(encoded, validate=True)
    backend.require(hashlib.new(algorithm, data).digest() == expected, "Dependency integrity differs")


def checked_packages(plan, folder):
    backend.require(not folder.is_symlink() and folder.is_dir(), "Dependency cache is not an owned directory")
    backend.require({p.name for p in folder.iterdir()} == set(plan), "Dependency object membership differs")
    result = {}
    total = 0
    for name, item in plan.items():
        data = backend.read_regular(folder / name, MAX_PACKAGE)
        check_integrity(data, item["integrity"])
        total += len(data)
        backend.require(total <= MAX_PACKAGES_TOTAL, "Dependency cache exceeds total bound")
        result[name] = {**item, **backend.record(data)}
    return {"object_count": len(result), "total_bytes": total, "objects": result}


def fetch_packages(inputs, folder, root=ROOT):
    plan = dependency_plan(lock_bytes(inputs, root), root)
    backend.new_scratch(folder, root)
    total = 0
    budget = Lock()
    def fetch(row):
        nonlocal total
        name, item = row
        request = urllib.request.Request(item["url"], headers={"User-Agent": "MostlyText-source-reproduction"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read(MAX_PACKAGE + 1)
        check_integrity(data, item["integrity"])
        with budget:
            total += len(data)
            backend.require(total <= MAX_PACKAGES_TOTAL, "Dependency cache exceeds total bound")
        with (folder / name).open("xb") as stream:
            stream.write(data)
        return len(data)
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(fetch, plan.items()))
    backend.require(total <= MAX_PACKAGES_TOTAL, "Dependency cache exceeds total bound")
    return checked_packages(plan, folder)


def recipe(original, root=ROOT):
    node = node_reference(root)
    lock = backend.audit(root)["build_source_sha256"]["package-lock.json"]
    extra = f'''
FROM {backend.IMAGE} AS wrapper
COPY {node['archive']} /src/node.tar.xz
RUN mkdir /node && tar -xJf /src/node.tar.xz --strip-components=1 --directory /node
ENV PATH="/node/bin:${{PATH}}"
COPY viz-source-99da545.tar.gz /src/source.tar.gz
RUN mkdir /src/source && tar -zxf /src/source.tar.gz --strip-components=1 --directory /src/source
COPY --from=viz /output/backend.js /src/source/packages/viz/lib/backend.js
WORKDIR /src/source/packages/viz
RUN echo "{lock}  /src/source/package-lock.json" | sha256sum -c -
COPY package-tarballs /package-tarballs
RUN find /package-tarballs -name '*.tgz' -print0 | xargs -0 -n16 npm cache add --ignore-scripts --offline --cache=/npm-cache --no-audit --no-fund
RUN npm clean-install --ignore-scripts --offline --cache=/npm-cache --no-audit --no-fund
RUN echo "{lock}  /src/source/package-lock.json" | sha256sum -c -
RUN test -f lib/backend.js && touch lib/backend.js && make
RUN echo "{lock}  /src/source/package-lock.json" | sha256sum -c -
RUN mkdir /wrapped && cp lib/backend.js lib/metadata.js dist/viz.js dist/viz.cjs dist/viz-global.js /wrapped/ && node --version > /wrapped/versions.txt && npm --version >> /wrapped/versions.txt
FROM scratch AS wrapper_export
COPY --from=wrapper /wrapped /
'''
    return backend.derive_recipe(original, root) + extra.encode()


def published_outputs(archive_path):
    with tarfile.open(archive_path) as archive:
        return {name: backend.record(backend.selected_member(archive, "package/" + path)) for name, path in GENERATED.items()}


def descriptor(output, root=ROOT):
    prior = backend.descriptor(output, root)
    backend.require(json.loads((output / "prepared.json").read_text()) == prior, "Original preparation differs")
    node = node_reference(root)
    context = output / "wrapper-context"
    names = set(prior["context"]) | {node["archive"], "viz-source-99da545.tar.gz"}
    backend.require({p.name for p in context.iterdir()} == names | {"package-tarballs"}, "Unexpected wrapper context members")
    original = backend.read_regular(output / "upstream-Dockerfile", backend.MAX_MEMBER)
    expected = dict(prior["context"])
    expected["Dockerfile"] = backend.record(recipe(original, root))
    expected[node["archive"]] = {"bytes": node["bytes"], "sha256": node["sha256"]}
    expected["viz-source-99da545.tar.gz"] = prior["archives"]["viz-source-99da545.tar.gz"]
    for name, identity in expected.items():
        backend.require(backend.record(backend.read_regular(context / name, identity["bytes"])) == identity, f"Wrapper context differs: {name}")
    npm_archive = output / "npm-input.tgz"
    npm_pin = prior["archives"]["viz-3.30.0.tgz"]
    backend.require(backend.record(backend.read_regular(npm_archive, npm_pin["bytes"])) == npm_pin, "npm input differs")
    with tarfile.open(context / "viz-source-99da545.tar.gz") as archive:
        data = backend.selected_member(archive, f"viz-js-{backend.REVISION}/package-lock.json")
        lock = check_lock(data, root)
        dependencies = checked_packages(dependency_plan(data, root), context / "package-tarballs")
    outputs = published_outputs(npm_archive)
    backend.require(outputs["backend.js"] == prior["expected_backend"], "Backend subject differs")
    resource = root / "MacDown2/Packages/MacDownKit/Sources/GraphvizRendering/Resources/viz-global.js"
    backend.require(backend.record(resource.read_bytes()) == outputs["viz-global.js"], "Current shipped renderer differs")
    return {"schema": 1, "backend_preparation": prior, "node": node, "lock": lock,
            "context": expected, "dependencies": dependencies, "expected_outputs": outputs,
            "tool_sha256": backend.sha(Path(__file__).read_bytes())}


def prepare(inputs, node_archive, packages, output, root=ROOT):
    node = node_reference(root)
    data = backend.read_regular(node_archive, node["bytes"])
    backend.require(backend.record(data) == {"bytes": node["bytes"], "sha256": node["sha256"]}, "Node archive differs")
    checked_packages(dependency_plan(lock_bytes(inputs, root), root), packages)
    backend.prepare(inputs, output, root)
    context = output / "wrapper-context"
    shutil.copytree(output / "context", context)
    shutil.copytree(packages, context / "package-tarballs")
    (context / node["archive"]).write_bytes(data)
    (context / "viz-source-99da545.tar.gz").write_bytes(backend.read_regular(inputs / "viz-source-99da545.tar.gz", 108597))
    (output / "npm-input.tgz").write_bytes(backend.read_regular(inputs / "viz-3.30.0.tgz", 1903630))
    (context / "Dockerfile").write_bytes(recipe((output / "upstream-Dockerfile").read_bytes(), root))
    result = descriptor(output, root)
    backend.write_json(output / "wrapper-prepared.json", result)
    return result


def compare_files(built, expected):
    backend.require({p.name for p in built.iterdir()} == set(expected) | {"versions.txt"}, "Generated file set differs")
    actual = {name: backend.record(backend.read_regular(built / name, backend.MAX_MEMBER)) for name in expected}
    versions = backend.read_regular(built / "versions.txt", 256).decode().splitlines()
    backend.require(len(versions) == 2 and versions[0] == "v24.19.0" and re.fullmatch(r"\d+\.\d+\.\d+", versions[1]), "Measured Node/npm versions differ")
    return {"actual_outputs": actual, "all_outputs_equal": actual == expected,
            "measured_versions": {"node": versions[0], "npm": versions[1]}}


def compare(output, built, root=ROOT):
    inputs = descriptor(output, root)
    backend.require(json.loads((output / "wrapper-prepared.json").read_text()) == inputs, "Wrapper preparation differs")
    result = {"schema": 1, "inputs": inputs, "scope": SCOPE, **compare_files(built, inputs["expected_outputs"])}
    head, run = os.environ.get("SOURCE_HEAD", ""), os.environ.get("GITHUB_RUN_ID", "")
    backend.require(re.fullmatch(r"[0-9a-f]{40}", head) and re.fullmatch(r"[0-9]+", run), "Invalid hosted identity")
    result["hosted"] = {"source_head": head, "run_id": run, "url": f"https://github.com/Joncallim/mostlytext/actions/runs/{run}"}
    backend.write_json(output / "wrapper-result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--inputs", type=Path, required=True)
    prep.add_argument("--node", type=Path, required=True)
    prep.add_argument("--packages", type=Path, required=True)
    prep.add_argument("--output", type=Path, required=True)
    prep.add_argument("--download", action="store_true")
    check = sub.add_parser("compare")
    check.add_argument("--output", type=Path, required=True)
    check.add_argument("--built", type=Path, required=True)
    fetch = sub.add_parser("fetch-packages")
    fetch.add_argument("--inputs", type=Path, required=True)
    fetch.add_argument("--packages", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        if args.download:
            backend.download(args.inputs)
            node = node_reference()
            with urllib.request.urlopen(node["url"], timeout=120) as response:
                data = response.read(node["bytes"] + 1)
            backend.require(backend.record(data) == {"bytes": node["bytes"], "sha256": node["sha256"]}, "Downloaded Node differs")
            with args.node.open("xb") as stream:
                stream.write(data)
            fetch_packages(args.inputs, args.packages)
        result = prepare(args.inputs, args.node, args.packages, args.output)
    elif args.command == "fetch-packages":
        result = fetch_packages(args.inputs, args.packages)
    else:
        result = compare(args.output, args.built)
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.command == "compare" and not result["all_outputs_equal"]:
        raise SystemExit("Generated runtime differs; complete receipt preserved")


if __name__ == "__main__":
    main()

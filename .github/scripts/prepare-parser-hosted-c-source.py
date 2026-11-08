#!/usr/bin/env python3
"""Stage the immutable hosted parser graph for a separate pure-C source proof."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


REPOSITORY = "Joncallim/mostlytext"
REF = "refs/heads/epic/05-parser-hosted-graph"
GRAPH_RUN = 42487278217
GRAPH_CHECKOUT = "e9a294d84f0cfb54bc8610a92461aa848fcacfec"
ARTIFACT_HASHES = {
    "receipt.json": "521431332f32cbf8d0a28252914c536e31279d028c081549eb3c11c938828ffa",
    "resolve.stdout": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "resolve.stderr": "12d9e03d9b64ac66f52bbc613e20518377a06c09d215d178db8f573f13efc096",
    "Packages/MacDownKit/Package.resolved": "1e0e187f55661e3e63e2a862853553a158d583c84055ff6cf3ebe877619e39be",
    "Packages/MacDownKit/Package.swift": "1626d803a479966a6042c93d5c33850e72ada5c08bf63d1690add548ff507888",
    "Packages/TreeSitterMarkdown/Package.swift": "02aa8e8cfb39edaf595c0026a44ddd1a4dddaa83bac992fe94f2893a61a65e89",
}
SOURCE = {
    "tree-sitter": {
        "url": "https://github.com/Joncallim/tree-sitter",
        "ref": "refs/heads/fix/lookahead-utf16-correctness",
        "revision": "1884982a418525e2e251ba331da929fccd354f3f",
        "tree": "6ab06e2a3bd3af27207829694ef1899f110998d1",
        "blobs": {"LICENSE": "451fe1d26ee6043ac94f6c8a81a6143f17748b4d",
                  "lib/src/unicode/LICENSE": "2e01e368768a4b992e22f98c05ead747134492a6",
                  "lib/src/parser.c": "baae969a74cb9c87c431e292cff04d8f8013b9a1",
                  "lib/src/unicode.h": "196c6bf416b6bf7c2e4efcd67a5ef083a90f49ab"},
    },
    "swifttreesitter": {
        "url": "https://github.com/Joncallim/SwiftTreeSitter",
        "ref": "refs/heads/fix/pinned-parser-correctness",
        "revision": "7cf83c59f1d7b6fdbd6ae3b0e212c9824fbf103d",
        "tree": "6fc812ba97d55f93e2fe15950285bb9549eae388",
        "blobs": {"LICENSE": "79ee939a3dccd21b2b6a5a69809b65afca15f389",
                  "Package.swift": "b0ff92c7e0731a39a52f443525e8e4b7ef29ba86"},
    },
    "neon": {
        "url": "https://github.com/Joncallim/Neon",
        "ref": "refs/heads/fix/pinned-parser-correctness",
        "revision": "7afa1dc49511a0d154f38810725d6984968ec2e6",
        "tree": "838fc45986276ccfe69469e2f8aaca6997886d34",
        "blobs": {"LICENSE": "9093e8c1fc4fa72473b691e46de86d1b9f697cc0",
                  "Package.swift": "6c71ade94eca29f3eab864d5942b6d522c478b97"},
    },
}
ORIGINAL_SHA = {
    "MacDownKit": "3d43404c0a1396bbac7a1c0d052ebc31bc2c931e0ebc407356a305a5aa87d284",
    "TreeSitterMarkdown": "0c28b2050f598318402bd9266a4c4adec0060afc1dad904d7b251bd1ffb5c8d8",
    "lock": "0a878dfe4a355ae18d0521d37540f414355180c1273baaddde313ec5460c96a4",
}


def command(arguments, **kwargs):
    return subprocess.check_output(arguments, text=True, **kwargs).strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_artifact(graph):
    for name, expected in ARTIFACT_HASHES.items():
        path = graph / name
        if not path.is_file() or sha256(path) != expected:
            raise ValueError("First hosted graph artifact changed or is incomplete: " + name)
    receipt = json.loads((graph / "receipt.json").read_text())
    if (receipt.get("checkout") != GRAPH_CHECKOUT or receipt.get("status") != "qualified"
            or receipt.get("resolve_exit") != 0
            or receipt.get("resolved_lock_sha256") != ARTIFACT_HASHES["Packages/MacDownKit/Package.resolved"]
            or receipt.get("original_lock_sha256") != ORIGINAL_SHA["lock"]):
        raise ValueError("First hosted graph receipt is not the reviewed success")
    for name, facts in SOURCE.items():
        if receipt["remote_heads"].get(name) != {key: facts[key] for key in ("url", "ref", "revision")}:
            raise ValueError("First hosted graph remote head changed: " + name)
        if receipt["resolved_parser_revisions"].get(name) != facts["revision"]:
            raise ValueError("First hosted graph revision changed: " + name)
    return receipt


def require_host(root):
    environment = os.environ
    if (environment.get("GITHUB_ACTIONS") != "true"
            or environment.get("GITHUB_EVENT_NAME") != "push"
            or environment.get("GITHUB_REPOSITORY") != REPOSITORY
            or environment.get("GITHUB_REF") != REF):
        raise ValueError("Only the owner parser-graph push can run the C source proof")
    workspace = Path(environment["GITHUB_WORKSPACE"]).resolve()
    temporary = Path(environment["RUNNER_TEMP"]).resolve()
    if Path.cwd().resolve() != workspace or root != temporary / "parser-c-source":
        raise ValueError("Unexpected checkout or temporary path")
    if command(["git", "rev-parse", "HEAD"], cwd=workspace) != environment.get("GITHUB_SHA"):
        raise ValueError("Checkout does not match the push event")
    return workspace, environment["GITHUB_SHA"]


def verify_remote_sources(root):
    facts = {}
    source_root = root / "remote-source"
    source_root.mkdir()
    for name, expected in SOURCE.items():
        lines = command(["git", "ls-remote", "--heads", expected["url"], expected["ref"]], timeout=30).splitlines()
        if lines != [expected["revision"] + "\t" + expected["ref"]]:
            raise ValueError("Remote fork head changed: " + name)
        bare = source_root / name
        subprocess.run(["git", "init", "--bare", "--quiet", str(bare)], check=True)
        subprocess.run(["git", "-C", str(bare), "fetch", "--quiet", "--no-tags", "--depth=1",
                        expected["url"], expected["revision"]], check=True, timeout=120)
        tree = command(["git", "-C", str(bare), "rev-parse", expected["revision"] + "^{tree}"])
        if tree != expected["tree"]:
            raise ValueError("Remote fork tree changed: " + name)
        blobs = {}
        for path, blob in expected["blobs"].items():
            found = command(["git", "-C", str(bare), "rev-parse", expected["revision"] + ":" + path])
            if found != blob:
                raise ValueError("Remote fork source/license blob changed: " + name + ":" + path)
            blobs[path] = found
        facts[name] = {"revision": expected["revision"], "tree": tree, "blobs": blobs}
    (root / "remote-sources.json").write_text(json.dumps(facts, indent=2, sort_keys=True) + "\n")
    return facts


def stage(root, graph, checkout):
    subprocess.run(["git", "-C", str(checkout), "worktree", "add", "--detach",
                    str(root / "checkout"), os.environ["GITHUB_SHA"]], check=True, timeout=120)
    staged = root / "checkout"
    if command(["git", "rev-parse", "HEAD"], cwd=staged) != os.environ["GITHUB_SHA"]:
        raise ValueError("Disposable checkout differs from the push")
    original = {
        "MacDownKit": staged / "MacDown2/Packages/MacDownKit/Package.swift",
        "TreeSitterMarkdown": staged / "MacDown2/Packages/TreeSitterMarkdown/Package.swift",
        "lock": staged / "MacDown2/Packages/MacDownKit/Package.resolved",
    }
    for name, path in original.items():
        if sha256(path) != ORIGINAL_SHA[name]:
            raise ValueError("Application graph changed since the first resolver: " + name)
    overlay = {
        "MacDownKit": graph / "Packages/MacDownKit/Package.swift",
        "TreeSitterMarkdown": graph / "Packages/TreeSitterMarkdown/Package.swift",
        "lock": graph / "Packages/MacDownKit/Package.resolved",
    }
    for name, path in original.items():
        shutil.copyfile(overlay[name], path)
    changed = command(["git", "diff", "--name-only"], cwd=staged).splitlines()
    if changed != ["MacDown2/Packages/MacDownKit/Package.resolved",
                   "MacDown2/Packages/MacDownKit/Package.swift",
                   "MacDown2/Packages/TreeSitterMarkdown/Package.swift"]:
        raise ValueError("Disposable checkout changed an unreviewed file")
    return {"checkout": str(staged), "changed_files": changed,
            "sha256": {name: sha256(path) for name, path in original.items()}}


def main(root):
    receipt = {"status": "started", "graph_run": GRAPH_RUN,
               "artifact_sha256": ARTIFACT_HASHES}
    destination = root / "preparation.json"
    try:
        checkout, head = require_host(root)
        receipt["source_checkout"] = head
        receipt["graph"] = validate_artifact(root / "graph")["resolved_parser_revisions"]
        receipt["remote_sources"] = verify_remote_sources(root)
        receipt["stage"] = stage(root, root / "graph", checkout)
        receipt["status"] = "prepared"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["failure"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        destination.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return receipt


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: prepare-parser-hosted-c-source.py OUTPUT_DIR")
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    try:
        print(json.dumps(main(output), indent=2, sort_keys=True))
    except Exception as error:
        print(f"Parser C source preparation refused: {error}", file=sys.stderr)
        raise SystemExit(1)

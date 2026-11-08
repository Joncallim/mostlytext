#!/usr/bin/env python3
"""Resolve the reviewed parser fork chain on a hosted macOS runner.

The application checkout is never rewritten. The first output is a receipt for
the current graph, before any app manifest or lockfile is committed.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


REPOSITORY = "Joncallim/mostlytext"
REF = "refs/heads/epic/05-parser-hosted-graph"
OLD = {
    "tree-sitter": ("https://github.com/Joncallim/tree-sitter", "3b1fb00f8c4f8907073f9b7342a807a0231867fa"),
    "swifttreesitter": ("https://github.com/Joncallim/SwiftTreeSitter", "76f93e7e325dcd05561a13ed63bcc92cb85be8da"),
    "neon": ("https://github.com/Joncallim/Neon", "6074d1a50c7076b2e59d8d0619554b542e096afa"),
}
NEW = {
    "tree-sitter": (OLD["tree-sitter"][0], "1884982a418525e2e251ba331da929fccd354f3f", "fix/lookahead-utf16-correctness"),
    "swifttreesitter": (OLD["swifttreesitter"][0], "7cf83c59f1d7b6fdbd6ae3b0e212c9824fbf103d", "fix/pinned-parser-correctness"),
    "neon": (OLD["neon"][0], "7afa1dc49511a0d154f38810725d6984968ec2e6", "fix/pinned-parser-correctness"),
}
PACKAGE = Path("MacDown2/Packages/MacDownKit")
MARKDOWN = Path("MacDown2/Packages/TreeSitterMarkdown")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pins(lock):
    rows = lock["pins"]
    identities = [row["identity"] for row in rows]
    if len(rows) != 24 or len(set(identities)) != 24:
        raise ValueError("Expected 24 unique dependency pins")
    return {row["identity"]: row for row in rows}


def verify_old_lock(lock):
    rows = pins(lock)
    for identity, (url, revision) in OLD.items():
        expected = {"identity": identity, "kind": "remoteSourceControl",
                    "location": url, "state": {"revision": revision}}
        if rows.get(identity) != expected:
            raise ValueError(f"Unexpected original {identity} pin")
    return rows


def verify_new_lock(original, resolved):
    before = verify_old_lock(original)
    after = pins(resolved)
    if resolved["version"] != original["version"] or set(after) != set(before):
        raise ValueError("Resolved lock changed its version or dependency set")
    for identity in before:
        expected = dict(before[identity])
        if identity in NEW:
            expected["state"] = {"revision": NEW[identity][1]}
        if after[identity] != expected:
            raise ValueError(f"Unreviewed resolved pin change: {identity}")
    if not isinstance(resolved.get("originHash"), str) or not resolved["originHash"]:
        raise ValueError("Resolved lock has no SwiftPM origin hash")
    return {identity: after[identity]["state"]["revision"] for identity in NEW}


def replace_once(text, old, new, label):
    if text.count(old) != 1 or new in text:
        raise ValueError(f"Unexpected original {label} manifest revision")
    return text.replace(old, new)


def stage_manifests(source, target):
    source_package = source / PACKAGE / "Package.swift"
    source_markdown = source / MARKDOWN / "Package.swift"
    package = (target / "MacDownKit/Package.swift")
    markdown = (target / "TreeSitterMarkdown/Package.swift")
    if source_package.read_bytes() != package.read_bytes() or source_markdown.read_bytes() != markdown.read_bytes():
        raise ValueError("Temporary manifests did not match the source")
    original_package = package.read_text()
    original_markdown = markdown.read_text()
    package_text = replace_once(original_package, OLD["swifttreesitter"][1], NEW["swifttreesitter"][1], "MacDownKit wrapper")
    package_text = replace_once(package_text, OLD["neon"][1], NEW["neon"][1], "MacDownKit Neon")
    markdown_text = replace_once(original_markdown, OLD["swifttreesitter"][1], NEW["swifttreesitter"][1], "Markdown wrapper")
    package.write_text(package_text)
    markdown.write_text(markdown_text)
    return {
        "MacDownKit": {"source_sha256": sha256(source_package), "staged_sha256": sha256(package)},
        "TreeSitterMarkdown": {"source_sha256": sha256(source_markdown), "staged_sha256": sha256(markdown)},
    }


def require_host(source, output):
    environment = os.environ
    if (environment.get("GITHUB_ACTIONS") != "true"
            or environment.get("GITHUB_EVENT_NAME") != "push"
            or environment.get("GITHUB_REPOSITORY") != REPOSITORY
            or environment.get("GITHUB_REF") != REF):
        raise ValueError("Only the owner parser-graph push may resolve this graph")
    workspace = Path(environment["GITHUB_WORKSPACE"]).resolve()
    temporary = Path(environment["RUNNER_TEMP"]).resolve()
    if source != workspace or output != temporary / "parser-hosted-graph":
        raise ValueError("Unexpected checkout or output location")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if head != environment.get("GITHUB_SHA"):
        raise ValueError("Checkout does not match the push event")
    return head


def require_remote_heads():
    result = {}
    for identity, (url, revision, branch) in NEW.items():
        ref = "refs/heads/" + branch
        rows = subprocess.check_output(["git", "ls-remote", "--heads", url, ref], text=True, timeout=30).splitlines()
        if rows != [revision + "\t" + ref]:
            raise ValueError(f"Remote {identity} branch is not at the reviewed commit")
        result[identity] = {"url": url, "ref": ref, "revision": revision}
    return result


def write_receipt(path, receipt):
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")


def resolve(source, output):
    receipt_path = output / "receipt.json"
    receipt = {"status": "started", "started_unix": int(time.time())}
    try:
        receipt["checkout"] = require_host(source, output)
        receipt["remote_heads"] = require_remote_heads()
        original_path = source / PACKAGE / "Package.resolved"
        original = json.loads(original_path.read_text())
        verify_old_lock(original)
        receipt["original_lock_sha256"] = sha256(original_path)

        destination = output / "Packages"
        shutil.copytree(source / "MacDown2/Packages", destination)
        staged_lock = destination / "MacDownKit/Package.resolved"
        if sha256(staged_lock) != receipt["original_lock_sha256"]:
            raise ValueError("Temporary lock differs before resolution")
        receipt["manifests"] = stage_manifests(source, destination)
        receipt["command"] = ["swift", "package", "--package-path", str(destination / "MacDownKit"), "resolve"]
        receipt["status"] = "resolving"
        write_receipt(receipt_path, receipt)
        with (output / "resolve.stdout").open("wb") as stdout, (output / "resolve.stderr").open("wb") as stderr:
            try:
                completed = subprocess.run(receipt["command"], cwd=source, stdout=stdout,
                                           stderr=stderr, timeout=900, check=False)
                receipt["resolve_exit"] = completed.returncode
            except subprocess.TimeoutExpired:
                receipt["status"] = "resolve_timeout"
                raise ValueError("SwiftPM resolve exceeded 900 seconds")
        receipt["resolved_lock_sha256"] = sha256(staged_lock)
        if receipt["resolve_exit"] != 0:
            raise ValueError("SwiftPM resolve failed")
        resolved = json.loads(staged_lock.read_text())
        receipt["resolved_parser_revisions"] = verify_new_lock(original, resolved)
        receipt["status"] = "qualified"
    except Exception as error:
        receipt["status"] = "failed" if receipt["status"] != "resolve_timeout" else receipt["status"]
        receipt["failure"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finished_unix"] = int(time.time())
        write_receipt(receipt_path, receipt)
    return receipt


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: resolve-parser-hosted-graph.py OUTPUT_DIR")
    destination = Path(sys.argv[1]).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    try:
        print(json.dumps(resolve(Path.cwd().resolve(), destination), indent=2, sort_keys=True))
    except Exception as error:
        print(f"Parser hosted resolution refused: {error}", file=sys.stderr)
        raise SystemExit(1)

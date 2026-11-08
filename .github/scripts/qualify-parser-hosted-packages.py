#!/usr/bin/env python3
"""Qualify the exact parser fork chain in disposable hosted macOS checkouts."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
MODULE = importlib.util.spec_from_file_location("parser_c_source", HERE / "prepare-parser-hosted-c-source.py")
parser_c = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(parser_c)

REPOSITORY = "Joncallim/mostlytext"
REF = "refs/heads/epic/05-parser-hosted-graph"
PARENTS = {
    "swifttreesitter": "76f93e7e325dcd05561a13ed63bcc92cb85be8da",
    "neon": "6074d1a50c7076b2e59d8d0619554b542e096afa",
}
MANIFEST_REVISIONS = {
    "swifttreesitter": ("3b1fb00f8c4f8907073f9b7342a807a0231867fa",
                          parser_c.SOURCE["tree-sitter"]["revision"]),
    "neon": (PARENTS["swifttreesitter"], parser_c.SOURCE["swifttreesitter"]["revision"]),
}
FORK_PINS = {
    "swifttreesitter": {"tree-sitter"},
    "neon": {"rearrange", "swifttreesitter", "tree-sitter"},
}
SUBMODULES = {
    "swifttreesitter": {"tree-sitter-swift": "eda05af7ac41adb4eb19c346883c0fa32fe3bdd8"},
    "neon": {"tree-sitter-swift": "50b8c5e61c29fa30e760c7a1cbf24b59970e6233"},
}
FAILURE = re.compile(r"(?:^|\s)(?:error:|fatal error:|FAILED|Test Case .* failed|Test .* failed|BUILD FAILED)", re.I)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(arguments, *, cwd=None, timeout=120):
    return subprocess.check_output(["git", *arguments], cwd=cwd, text=True, timeout=timeout).strip()


def git_bytes(arguments, *, cwd=None, timeout=120):
    return subprocess.check_output(["git", *arguments], cwd=cwd, timeout=timeout)


def write_receipt(path, receipt):
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")


def require_host(root):
    env = os.environ
    if (env.get("GITHUB_ACTIONS") != "true"
            or env.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or env.get("GITHUB_REPOSITORY") != REPOSITORY
            or env.get("GITHUB_REF") != REF):
        raise ValueError("Only a manual dispatch on the owner parser branch is allowed")
    workspace = Path(env["GITHUB_WORKSPACE"]).resolve()
    temporary = Path(env["RUNNER_TEMP"]).resolve()
    if Path.cwd().resolve() != workspace or root != temporary / "parser-package-qualification":
        raise ValueError("Unexpected checkout or temporary output path")
    if git(["rev-parse", "HEAD"], cwd=workspace) != env.get("GITHUB_SHA"):
        raise ValueError("Checkout does not match the dispatch event")
    if git(["status", "--porcelain"], cwd=workspace):
        raise ValueError("Tracked workflow checkout is not clean")
    return workspace, env["GITHUB_SHA"]


def verify_manifest_change(bare, name):
    expected = parser_c.SOURCE[name]
    revision = expected["revision"]
    parent = PARENTS[name]
    commit = git(["--git-dir", str(bare), "cat-file", "-p", revision])
    parents = [line.removeprefix("parent ") for line in commit.splitlines() if line.startswith("parent ")]
    if parents != [parent]:
        raise ValueError("Unexpected fork parent: " + name)
    subprocess.run(["git", "--git-dir", str(bare), "fetch", "--quiet", "--no-tags", "--depth=1",
                    expected["url"], parent], check=True, timeout=120)
    changed = git(["--git-dir", str(bare), "diff", "--name-only", parent, revision]).splitlines()
    if changed != ["Package.swift"]:
        raise ValueError("Fork changed files outside its manifest: " + name)
    original = git_bytes(["--git-dir", str(bare), "show", parent + ":Package.swift"])
    candidate = git_bytes(["--git-dir", str(bare), "show", revision + ":Package.swift"])
    old, new = MANIFEST_REVISIONS[name]
    old, new = old.encode(), new.encode()
    if original.count(old) != 1 or new in original or candidate != original.replace(old, new):
        raise ValueError("Fork manifest is not the one-pin revision change: " + name)
    return {"revision": revision, "parent": parent, "tree": expected["tree"],
            "changed_files": changed, "manifest_blob": expected["blobs"]["Package.swift"]}


def verify_submodule_status(lines, expected):
    """Require the initialized checkout to match each reviewed commit gitlink."""
    found = {}
    for line in lines:
        match = re.fullmatch(r" ([0-9a-f]{40}) ([^ ]+)(?: \([^\n]*\))?", line)
        if match is None:
            raise ValueError("Submodule is uninitialized or differs from its committed gitlink")
        revision, path = match.groups()
        if path in found:
            raise ValueError("Duplicate submodule path: " + path)
        found[path] = revision
    if found != expected:
        raise ValueError("Submodule path or gitlink differs from the reviewed commit")
    return found


def checkout_fork(root, name):
    bare = root / "remote-source" / name
    target = root / "forks" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    exact = verify_manifest_change(bare, name)
    subprocess.run(["git", "--git-dir", str(bare), "worktree", "add", "--quiet", "--detach",
                    str(target), exact["revision"]], check=True, timeout=120)
    if git(["rev-parse", "HEAD"], cwd=target) != exact["revision"]:
        raise ValueError("Fork checkout changed: " + name)
    subprocess.run(["git", "submodule", "update", "--init", "--recursive", "--depth=1"],
                   cwd=target, check=True, timeout=600)
    # git() strips whitespace; the first column here is a security-relevant
    # status marker, where one leading space means the checked-out gitlink.
    submodules = subprocess.check_output(["git", "submodule", "status", "--recursive"],
                                         cwd=target, text=True, timeout=30).splitlines()
    verified_submodules = verify_submodule_status(submodules, SUBMODULES[name])
    if git(["status", "--porcelain", "--untracked-files=no"], cwd=target):
        raise ValueError("Fork tracked source became dirty: " + name)
    exact["checkout"] = str(target)
    exact["submodules"] = verified_submodules
    exact["tracked_lock_before_sha256"] = sha256(target / "Package.resolved")
    return target, exact


def validate_lock(lock_path, expected_rows):
    lock = json.loads(lock_path.read_text())
    if lock.get("version") not in (2, 3):
        raise ValueError("Unexpected SwiftPM lock format")
    rows = lock["pins"]
    pins = {row["identity"]: row for row in rows}
    if len(rows) != len(pins) or set(pins) != set(expected_rows):
        raise ValueError("Resolved dependency set differs from the reviewed graph")
    for identity, expected in expected_rows.items():
        if pins[identity] != expected:
            raise ValueError("Resolved dependency differs from the reviewed pin: " + identity)
    if lock["version"] == 3 and not lock.get("originHash"):
        raise ValueError("Resolved lock is missing its manifest origin hash")
    return {"sha256": sha256(lock_path), "version": lock["version"],
            "origin_hash": lock.get("originHash"),
            "pins": {identity: pins[identity] for identity in sorted(pins)}}


def first_failure(path):
    for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if FAILURE.search(line) and not re.search(r"\b0 failures?\b", line, re.I):
            return {"line": number, "text": line[:1000]}
    return None


def copy_owned_helper(helper, owned):
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise ValueError("Installed Swift Testing helper is not executable")
    shutil.copy2(helper, owned)
    if sha256(helper) != sha256(owned) or not os.access(owned, os.X_OK):
        raise ValueError("Owned Swift Testing helper differs or is not executable")


def run_logged(receipt, receipt_path, label, command, cwd, timeout, *, env=None):
    log = receipt_path.parent / (label + ".log")
    record = {"command": command, "cwd": str(cwd), "log": log.name,
              "started_unix": int(time.time()), "timeout_seconds": timeout}
    receipt["commands"].append(record)
    write_receipt(receipt_path, receipt)
    with log.open("wb") as output:
        process = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True, env=env)
        try:
            record["exit"] = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            record["timeout"] = True
            record["exit"] = 124
    record["finished_unix"] = int(time.time())
    record["log_sha256"] = sha256(log)
    record["first_failure"] = first_failure(log) if record["exit"] else None
    write_receipt(receipt_path, receipt)
    if record["exit"] != 0:
        receipt["first_failed_command"] = label
        raise ValueError(f"{label} exited {record['exit']}; see {log.name}")
    return record


def qualify_fork(root, receipt, receipt_path, name, graph_lock):
    checkout, facts = checkout_fork(root, name)
    receipt["forks"][name] = facts
    write_receipt(receipt_path, receipt)
    original_lock = json.loads((checkout / "Package.resolved").read_text())
    original_rows = {row["identity"]: row for row in original_lock["pins"]}
    graph_rows = {row["identity"]: row for row in graph_lock["pins"]}
    expected_rows = {identity: (original_rows[identity] if identity == "rearrange" else graph_rows[identity])
                     for identity in FORK_PINS[name]}
    run_logged(receipt, receipt_path, name + "-resolve", ["swift", "package", "resolve"], checkout, 1200)
    lock_path = checkout / "Package.resolved"
    facts["resolved_lock"] = validate_lock(lock_path, expected_rows)
    if git(["diff", "--name-only"], cwd=checkout).splitlines() != ["Package.resolved"]:
        raise ValueError("Fork resolve changed files beyond the stale tracked lock: " + name)
    write_receipt(receipt_path, receipt)
    run_logged(receipt, receipt_path, name + "-test",
               ["swift", "test", "--no-parallel", "--force-resolved-versions"], checkout, 1800)
    if sha256(lock_path) != facts["resolved_lock"]["sha256"]:
        raise ValueError("Fork tests changed the resolved lock: " + name)
    if git(["diff", "--name-only"], cwd=checkout).splitlines() != ["Package.resolved"]:
        raise ValueError("Fork tests changed tracked source: " + name)
    return facts


def qualify_app(root, receipt, receipt_path, workspace, graph_lock):
    facts = parser_c.stage(root, root / "graph", workspace)
    receipt["app"] = facts
    checkout = Path(facts["checkout"])
    package = checkout / "MacDown2/Packages/MacDownKit"
    lock_path = package / "Package.resolved"
    lock_before = sha256(lock_path)
    if lock_before != parser_c.ARTIFACT_HASHES["Packages/MacDownKit/Package.resolved"]:
        raise ValueError("Staged app lock is not the reviewed artifact")
    write_receipt(receipt_path, receipt)
    run_logged(receipt, receipt_path, "macdownkit-resolve", ["swift", "package", "resolve"], package, 1200)
    if sha256(lock_path) != lock_before:
        raise ValueError("Staged MacDownKit lock changed on fresh resolve")
    facts["resolved_lock"] = validate_lock(lock_path,
                                             {row["identity"]: row for row in graph_lock["pins"]})
    run_logged(receipt, receipt_path, "macdownkit-build",
               ["swift", "build", "--force-resolved-versions"], package, 1800)
    run_logged(receipt, receipt_path, "macdownkit-build-tests",
               ["swift", "build", "--build-tests", "--force-resolved-versions"], package, 1800)
    bin_path = git_swift_bin_path(receipt, receipt_path, package)
    test_host = Path(bin_path) / "MacDownKitPackageTests.xctest/Contents/MacOS/MacDownKitPackageTests"
    if not test_host.is_file():
        raise ValueError("Built MacDownKit test host is absent")
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    helper = developer / "Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
    owned = root / "owned-swiftpm-testing-helper"
    copy_owned_helper(helper, owned)
    run_logged(receipt, receipt_path, "macdownkit-sign-helper",
               ["codesign", "--force", "--sign", "-", str(owned)], root, 60)
    run_logged(receipt, receipt_path, "macdownkit-verify-helper",
               ["codesign", "--verify", "--strict", str(owned)], root, 60)
    facts["test_host"] = {"path": str(test_host), "sha256": sha256(test_host)}
    facts["installed_helper_sha256"] = sha256(helper)
    facts["owned_helper_sha256"] = sha256(owned)
    write_receipt(receipt_path, receipt)
    run_logged(receipt, receipt_path, "macdownkit-xctest",
               ["swift", "test", "--skip-build", "--disable-swift-testing", "--no-parallel",
                "--force-resolved-versions"], package, 1800)
    frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
    if not (frameworks / "Testing.framework").is_dir():
        raise ValueError("Xcode Testing.framework is absent")
    environment = dict(os.environ, DYLD_FRAMEWORK_PATH=str(frameworks))
    run_logged(receipt, receipt_path, "macdownkit-swift-testing",
               ["python3", str(checkout / ".github/scripts/run-owned-package-tests.py"),
                str(root / "owned-package-test-result"), str(owned),
                "--test-bundle-path", str(test_host), "--testing-library", "swift-testing", "--no-parallel"],
               package, 3600, env=environment)
    status = json.loads((root / "owned-package-test-result/status.json").read_text())
    if status != {"returncode": 0}:
        raise ValueError("Owned Swift Testing host did not pass")
    if sha256(helper) != facts["installed_helper_sha256"] or sha256(test_host) != facts["test_host"]["sha256"]:
        raise ValueError("Installed helper or package test host changed")
    if sha256(lock_path) != lock_before or git(["diff", "--name-only"], cwd=checkout).splitlines() != facts["changed_files"]:
        raise ValueError("App tests changed the staged dependency graph or tracked source")
    return facts


def git_swift_bin_path(receipt, receipt_path, package):
    result = run_logged(receipt, receipt_path, "macdownkit-bin-path",
                        ["swift", "build", "--show-bin-path", "--force-resolved-versions"], package, 120)
    for line in reversed((receipt_path.parent / result["log"]).read_text().splitlines()):
        candidate = Path(line.strip())
        if candidate.is_absolute():
            path = candidate.resolve()
            if path.is_dir() and path.is_relative_to(package):
                return path
    raise ValueError("SwiftPM binary path is outside the disposable package")


def main(root):
    root.mkdir(parents=True, exist_ok=True)  # The artifact download creates graph/ first.
    receipt_path = root / "receipt.json"
    if receipt_path.exists():
        raise ValueError("Qualification receipt already exists")
    receipt = {"status": "started", "started_unix": int(time.time()),
               "graph_run": parser_c.GRAPH_RUN, "commands": [], "forks": {}}
    try:
        workspace, head = require_host(root)
        receipt["source_checkout"] = head
        receipt["toolchain"] = {
            "macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
            "architecture": subprocess.check_output(["uname", "-m"], text=True).strip(),
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
            "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
        }
        if (not receipt["toolchain"]["macos"].startswith("26.")
                or receipt["toolchain"]["architecture"] != "arm64"
                or not receipt["toolchain"]["xcode"].startswith("Xcode 26.6\n")):
            raise ValueError("Required macOS 26 ARM / Xcode 26.6 host is unavailable")
        receipt["graph"] = parser_c.validate_artifact(root / "graph")
        graph_lock = json.loads((root / "graph/Packages/MacDownKit/Package.resolved").read_text())
        receipt["remote_sources"] = parser_c.verify_remote_sources(root)
        for name in ("swifttreesitter", "neon"):
            qualify_fork(root, receipt, receipt_path, name, graph_lock)
        qualify_app(root, receipt, receipt_path, workspace, graph_lock)
        receipt["status"] = "qualified"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["failure"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finished_unix"] = int(time.time())
        write_receipt(receipt_path, receipt)
    return receipt


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: qualify-parser-hosted-packages.py OUTPUT_DIR")
    try:
        print(json.dumps(main(Path(sys.argv[1]).resolve()), indent=2, sort_keys=True))
    except Exception as error:
        print(f"Parser package qualification failed: {error}", file=sys.stderr)
        raise SystemExit(1)

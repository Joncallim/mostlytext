#!/usr/bin/env python3
"""Check actual C parser comparison semantics, bounded work and sanitizer behavior."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile

BASE = "5ce80b6f0e29096a5f06826a3ba610c4e89bc255"
OWNERS = {
    "tree-sitter": "https://github.com/Joncallim/tree-sitter",
    "tree-sitter-json": "https://github.com/tree-sitter/tree-sitter-json",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_pins(lock):
    rows = lock["pins"]
    pins = {row["identity"]: row for row in rows}
    if len(pins) != len(rows):
        raise SystemExit("Duplicate dependency identities cannot qualify runtime proof")
    if len(pins) != 24:
        raise SystemExit("The reviewed complete 24-pin graph is required")
    for name, owner in OWNERS.items():
        row = pins.get(name, {})
        revision = row.get("state", {}).get("revision", "")
        if row.get("location") != owner or not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise SystemExit("The exact reviewed runtime/grammar owner and revision are required: " + name)
    if pins["tree-sitter"]["state"]["revision"] == BASE:
        raise SystemExit("An unchanged original runtime cannot qualify the shared-work repair")
    return pins


def inventory(repo):
    names = subprocess.check_output([
        "git", "ls-files", "MacDown2", ".github/scripts/run-shared-subtree-comparison-probe.py",
        ".github/scripts/test-shared-subtree-pin-review.py", ".github/workflows/shared-subtree-comparison.yml",
        "compliance/inventory.json", "compliance/licenses/tree-sitter--LICENSE.txt",
    ], cwd=repo, text=True).splitlines()
    return {name: digest(repo / name) for name in sorted(set(names))}


def command(arguments, output, expected=0, timeout=180, separate_stderr=False):
    with output.open("x") as log, output.with_suffix(".stderr.log").open("x") as errors:
        result = subprocess.run(arguments, stdout=log,
                                stderr=errors if separate_stderr else subprocess.STDOUT, timeout=timeout)
    output.with_suffix(output.suffix + ".status.json").write_text(json.dumps({
        "command": arguments, "returncode": result.returncode, "expected": expected,
    }, indent=2) + "\n")
    if result.returncode != expected:
        raise SystemExit("Unexpected result; original output retained: " + str(output))


def fetch(owner, revisions, destination):
    subprocess.run(["git", "init", "--quiet", str(destination)], check=True)
    for revision in revisions:
        subprocess.run(["git", "-C", str(destination), "fetch", "--quiet", "--no-tags", "--depth=1",
                        owner, revision], check=True, timeout=180)


def extract(repository, revision, destination):
    raw = subprocess.check_output(["git", "-C", str(repository), "archive", revision])
    destination.mkdir()
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        archive.extractall(destination, filter="data")


def verify_linkage(binary, output):
    arguments = ["otool", "-L", str(binary)] if platform.system() == "Darwin" else ["ldd", str(binary)]
    linked = subprocess.check_output(arguments, text=True)
    output.write_text(linked)
    if any(name in linked for name in ["AppKit", "SwiftUI", "WebKit", "CoreText", "CoreGraphics",
                                       "QuartzCore", "libgtk", "libQt", "libX11"]):
        raise SystemExit("The standalone C probe unexpectedly links a GUI library")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=False)
    output = args.output.resolve()
    sources = inventory(repo)
    lock = json.loads((repo / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())
    pins = checked_pins(lock)
    candidate = pins["tree-sitter"]["state"]["revision"]
    grammar_revision = pins["tree-sitter-json"]["state"]["revision"]
    checkout = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    receipt = {"checkout": checkout, "source_sha256": sources, "pins": lock["pins"],
               "runtime_original": BASE, "runtime_candidate": candidate,
               "grammar_revision": grammar_revision, "results": []}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    runtime_git, grammar_git = output / "runtime.git", output / "grammar.git"
    fetch(OWNERS["tree-sitter"], [BASE, candidate], runtime_git)
    fetch(OWNERS["tree-sitter-json"], [grammar_revision], grammar_git)
    delta = subprocess.check_output(["git", "-C", str(runtime_git), "diff", "--name-only", BASE, candidate,
                                     "--", "lib/src", "lib/include", "Package.swift"], text=True).splitlines()
    if delta != ["lib/src/subtree.c"]:
        raise SystemExit("An unreviewed runtime product or interface changed")
    original, current, grammar = output / "original", output / "candidate", output / "grammar"
    extract(runtime_git, BASE, original)
    extract(runtime_git, candidate, current)
    extract(grammar_git, grammar_revision, grammar)
    license_bytes = (repo / "compliance/licenses/tree-sitter--LICENSE.txt").read_bytes()
    if (original / "LICENSE").read_bytes() != license_bytes or (current / "LICENSE").read_bytes() != license_bytes:
        raise SystemExit("The original runtime licence changed")
    fixture = current / "lib/tests/subtree_compare_identity.c"
    receipt["fixture_sha256"] = digest(fixture)
    receipt["runtime_product_delta"] = delta
    receipt["runtime_subtree_sha256"] = {
        "original": digest(original / "lib/src/subtree.c"),
        "candidate": digest(current / "lib/src/subtree.c"),
    }
    receipt["grammar_source_sha256"] = {
        str(path.relative_to(grammar)): digest(path)
        for path in sorted((grammar / "src").rglob("*")) if path.is_file()
    }
    semantic = None
    for name, runtime, counted, sanitized in [
        ("original", original, False, False), ("candidate", current, False, False),
        ("original-work", original, True, False), ("candidate-work", current, True, False),
        ("candidate-sanitized", current, False, True),
    ]:
        runtime_source = runtime / "lib/src"
        if counted:
            runtime_source = output / (name + "-source")
            shutil.copytree(runtime / "lib/src", runtime_source)
            path = runtime_source / "subtree.c"
            text = path.read_text()
            declaration = "int ts_subtree_compare(Subtree left, Subtree right, SubtreePool *pool) {"
            step = "    left = ts_subtree_from_mut(array_pop(&pool->tree_stack));\n"
            if text.count(declaration) != 1 or text.count(step) != 1 or "comparison_visit_count" in text:
                raise SystemExit("The exact disposable comparison observation requires source review")
            path.write_text(text.replace(declaration, "uint64_t comparison_visit_count = 0;\n" + declaration)
                            .replace(step, step + "    comparison_visit_count++;\n"))
        binary = output / (name + "-probe")
        flags = ["-O1", "-g", "-fno-omit-frame-pointer", "-fsanitize=address,undefined"] if sanitized else ["-O2"]
        compile_command = ["clang", "-std=c11", "-D_DEFAULT_SOURCE", *flags,
                           *(["-DOBSERVE_COMPARISON_WORK"] if counted else []),
                           "-I" + str(runtime_source), "-I" + str(runtime / "lib/include"),
                           "-I" + str(grammar / "src"), str(fixture), str(grammar / "src/parser.c"),
                           "-o", str(binary)]
        command(compile_command, output / (name + "-compile.log"))
        verify_linkage(binary, output / (name + "-linked-libraries.txt"))
        executable_hash = digest(binary)
        expected = 2 if name == "original-work" else 0
        log = output / (name + ".log")
        command([str(binary)] + (["--require-bounded-self-comparison"] if counted else []),
                log, expected=expected, timeout=60, separate_stderr=True)
        stdout, stderr = log.read_text(), log.with_suffix(".stderr.log").read_text()
        text = stdout + "\n" + stderr
        pairs = [line for line in stdout.splitlines() if line.startswith("compare ")]
        if len(pairs) != 324 or (semantic is not None and pairs != semantic):
            raise SystemExit("Actual comparison ordering or complete selection differs")
        semantic = pairs
        nodes = None
        if counted:
            match = re.search(r"SHARED_SUBTREE_WORK nodes=(\d+)", text)
            if match is None:
                raise SystemExit("Actual comparison work did not execute")
            nodes = int(match[1])
            if (name == "original-work" and nodes <= 1000) or (name == "candidate-work" and nodes > 4):
                raise SystemExit("The original/candidate work regression was not demonstrated")
            expected_failure = "Identical shared document descendants were traversed again"
            if (expected_failure in stderr) != (name == "original-work"):
                raise SystemExit("The exact intended original work failure was not preserved")
        elif "Actual tree comparison ordering, distinct equality, shared identity and reference ownership pass" not in text:
            raise SystemExit("A required semantic or ownership control did not finish")
        if sanitized and stderr:
            raise SystemExit("A sanitizer error prevents qualification")
        if digest(binary) != executable_hash or digest(fixture) != receipt["fixture_sha256"] or inventory(repo) != sources:
            raise SystemExit("Execution inputs or products changed")
        receipt["results"].append({"phase": name, "returncode": expected, "ordering_pairs": len(pairs),
                                    "comparison_nodes": nodes, "binary_sha256": executable_hash})
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if (output / "candidate.log").read_bytes() != (output / "original.log").read_bytes():
        raise SystemExit("Complete semantic output differs from the original runtime")
    if (output / "candidate-sanitized.log").read_bytes() != (output / "candidate.log").read_bytes():
        raise SystemExit("Sanitized behavior differs from the unchanged candidate")
    receipt["qualified"] = True
    receipt["scope"] = "C runtime semantics, ownership and work only; native and product latency gates remain separate"
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Complete original/candidate C semantics, ownership, work regression and sanitizers pass")


if __name__ == "__main__":
    main()

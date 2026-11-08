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
COMBINED_BASE = "3b1fb00f8c4f8907073f9b7342a807a0231867fa"
REVIEWED_PRODUCT_DELTA = ["Package.swift", "lib/src/parser.c", "lib/src/subtree.c", "lib/src/unicode.h"]
REVIEWED_PARENT_DELTA = ["MOSTLYTEXT_PATCHES.md", "lib/src/parser.c", "lib/src/unicode.h",
                         "lib/tests/utf16_decoder_boundaries.c"]
OWNERS = {
    "tree-sitter": "https://github.com/Joncallim/tree-sitter",
    "tree-sitter-json": "https://github.com/tree-sitter/tree-sitter-json",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise SystemExit("The exact upstream runtime patch no longer applies once")
    return source.replace(old, new, 1)


def reviewed_parser_source(source):
    old = b"    } else if (ts_parser__has_included_range_difference(self, byte_offset, end_byte_offset)) {\n"
    new = (b"    } else if (ts_parser__has_included_range_difference(\n"
           b"                 self,\n"
           b"                 byte_offset,\n"
           b"                 ts_subtree_is_eof(result)\n"
           b"                   ? end_byte_offset\n"
           b"                   : end_byte_offset + ts_subtree_lookahead_bytes(result)\n"
           b"               )) {\n")
    return replace_once(source, old, new)


def reviewed_unicode_source(source):
    old_trail = b"if((i)!=(length) && U16_IS_TRAIL(__c2=(s)[(i)]))"
    if source.count(old_trail) != 2:
        raise SystemExit("Both original UTF-16 trailing-surrogate reads are required")
    expected = source.replace(old_trail,
                              b"if((i)!=(length) && U16_IS_TRAIL(__c2=le16toh((s)[(i)])))", 1)
    expected = replace_once(expected, old_trail,
                            b"if((i)!=(length) && U16_IS_TRAIL(__c2=be16toh((s)[(i)])))")
    for endian in (b"LE", b"BE"):
        old = (b"  uint32_t i = 0;\n"
               b"  U16_NEXT_" + endian + b"(((uint16_t *)string), i, length, *code_point);\n"
               b"  return i * 2;\n")
        new = (b"  if (length < 2) {\n"
               b"    *code_point = TS_DECODE_ERROR;\n"
               b"    return length;\n"
               b"  }\n"
               b"  uint32_t i = 0;\n"
               b"  // length is in bytes; U16_NEXT indexes into uint16_t*, so its length\n"
               b"  // parameter must be in code units (length / 2), not bytes.\n"
               b"  U16_NEXT_" + endian + b"(((uint16_t *)string), i, length / 2, *code_point);\n"
               b"  return i * 2;\n")
        expected = replace_once(expected, old, new)
    return expected


def require_reviewed_runtime_source(parent, current, repo):
    for name, transform in [("parser.c", reviewed_parser_source),
                            ("unicode.h", reviewed_unicode_source)]:
        old = (parent / "lib/src" / name).read_bytes()
        actual = (current / "lib/src" / name).read_bytes()
        if transform(old) != actual:
            raise SystemExit("An unreviewed parser or Unicode source change was found: " + name)
    fixture = repo / ".github/c-probes/utf16-decoder-boundary.c"
    if (current / "lib/tests/utf16_decoder_boundaries.c").read_bytes() != fixture.read_bytes():
        raise SystemExit("The owner fork's UTF-16 regression fixture changed")


def require_reviewed_delta(delta, parent_delta):
    if delta != REVIEWED_PRODUCT_DELTA or parent_delta != REVIEWED_PARENT_DELTA:
        raise SystemExit("The reviewed C runtime fork contains an extra or missing file")


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
        ".github/c-probes/markdown-lookahead-reuse.c", ".github/c-probes/utf16-decoder-boundary.c",
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


def run_correctness_probes(repo, output, parent, current, receipt, sources):
    markdown_src = repo / "MacDown2/Packages/TreeSitterMarkdown/Sources/TreeSitterMarkdownInline/src"
    markdown_driver = repo / ".github/c-probes/markdown-lookahead-reuse.c"
    decoder_driver = repo / ".github/c-probes/utf16-decoder-boundary.c"
    for phase, runtime, sanitized in [
        ("parent", parent, False), ("candidate", current, False),
        ("candidate-sanitized", current, True),
    ]:
        flags = ["-O1", "-g", "-fno-omit-frame-pointer", "-fsanitize=address,undefined"] if sanitized else ["-O2"]
        for kind, driver in [("markdown", markdown_driver), ("utf16", decoder_driver)]:
            name = kind + "-" + phase
            binary = output / (name + "-probe")
            arguments = ["clang", "-std=c11", "-D_DEFAULT_SOURCE", *flags,
                         "-I" + str(runtime / "lib/src"), "-I" + str(runtime / "lib/include")]
            if kind == "markdown":
                arguments += ["-I" + str(markdown_src), str(driver),
                              str(markdown_src / "parser.c"), str(markdown_src / "scanner.c"),
                              str(runtime / "lib/src/lib.c"), str(runtime / "lib/src/wasm/stdlib.c")]
            else:
                arguments += ["-Wall", "-Wextra", "-Werror", str(driver)]
            arguments += ["-o", str(binary)]
            command(arguments, output / (name + "-compile.log"))
            verify_linkage(binary, output / (name + "-linked-libraries.txt"))
            binary_hash = digest(binary)
            expected = 65 if phase == "parent" else 0
            log = output / (name + ".log")
            command([str(binary)], log, expected=expected, timeout=10, separate_stderr=True)
            stdout, stderr = log.read_text(), log.with_suffix(".stderr.log").read_text()
            if kind == "markdown":
                report = json.loads(stdout)
                cases = report["cases"]
                failures = report["semantic_failures"]
                if len(cases) != 8 or failures != (16 if phase == "parent" else 0):
                    raise SystemExit("The exact Markdown included-range failure/correction was not reproduced")
                if phase != "parent" and any(
                    not (case["unchanged_equal"] and case["expanded_equal"] and case["shrunk_equal"]
                         and case["expanded_code_spans"] == case["fresh_code_spans"] == 1)
                    for case in cases
                ):
                    raise SystemExit("A corrected Markdown tree differs from its fresh reference")
            else:
                rows = [line for line in stdout.splitlines() if line.startswith("case=")]
                failures = sum(" pass=0" in line for line in rows)
                if len(rows) != 12 or failures != (6 if phase == "parent" else 0):
                    raise SystemExit("The exact UTF-16 decoder failure/correction was not reproduced")
                if "cases=12 failures=" + str(failures) not in stdout:
                    raise SystemExit("The UTF-16 decoder did not complete its full matrix")
            if sanitized:
                if any(marker in stderr for marker in ("AddressSanitizer:", "UndefinedBehaviorSanitizer:", "runtime error:", "ERROR:")):
                    raise SystemExit("A corrected parser produced a sanitizer finding")
            if digest(binary) != binary_hash or inventory(repo) != sources:
                raise SystemExit("C correctness source or binary changed during execution")
            receipt["results"].append({"phase": name, "returncode": expected,
                                       "cases": len(cases) if kind == "markdown" else len(rows),
                                       "semantic_failures": failures, "binary_sha256": binary_hash,
                                       "stdout_sha256": digest(log),
                                       "stderr_sha256": digest(log.with_suffix(".stderr.log"))})
            (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        if sanitized:
            binary = output / ("utf16-" + phase + "-probe")
            for endian in ("le", "be"):
                name = "utf16-true-two-byte-" + endian
                log = output / (name + ".log")
                command([str(binary), "--true-two-byte-" + endian], log,
                        timeout=10, separate_stderr=True)
                if any(marker in log.with_suffix(".stderr.log").read_text()
                       for marker in ("AddressSanitizer:", "UndefinedBehaviorSanitizer:", "runtime error:", "ERROR:")):
                    raise SystemExit("A true two-byte UTF-16 chunk over-read")
                receipt["results"].append({"phase": name, "returncode": 0,
                                           "stdout_sha256": digest(log),
                                           "stderr_sha256": digest(log.with_suffix(".stderr.log"))})
                (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


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
    fetch(OWNERS["tree-sitter"], [BASE, COMBINED_BASE, candidate], runtime_git)
    fetch(OWNERS["tree-sitter-json"], [grammar_revision], grammar_git)
    delta = subprocess.check_output(["git", "-C", str(runtime_git), "diff", "--name-only", BASE, candidate,
                                     "--", "lib/src", "lib/include", "Package.swift"], text=True).splitlines()
    parent_delta = subprocess.check_output([
        "git", "-C", str(runtime_git), "diff", "--name-only", COMBINED_BASE, candidate,
    ], text=True).splitlines()
    require_reviewed_delta(delta, parent_delta)
    original, parent, current, grammar = (
        output / "original", output / "combined-parent", output / "candidate", output / "grammar"
    )
    extract(runtime_git, BASE, original)
    extract(runtime_git, COMBINED_BASE, parent)
    extract(runtime_git, candidate, current)
    extract(grammar_git, grammar_revision, grammar)
    require_reviewed_runtime_source(parent, current, repo)
    license_bytes = (repo / "compliance/licenses/tree-sitter--LICENSE.txt").read_bytes()
    if any((directory / "LICENSE").read_bytes() != license_bytes
           for directory in (original, parent, current)):
        raise SystemExit("The original runtime licence changed")
    original_manifest = (original / "Package.swift").read_bytes()
    expected_manifest = original_manifest.replace(b'                        "src/lib.c",\n', b'')
    expected_manifest = expected_manifest.replace(b'sources: ["src"]', b'sources: ["src/lib.c", "src/wasm/stdlib.c"]')
    if expected_manifest == original_manifest or (current / "Package.swift").read_bytes() != expected_manifest:
        raise SystemExit("The exact reviewed combined compilation source list is required")
    included = re.findall(r'#include "\./([^"\n]+)"', (current / "lib/src/lib.c").read_text())
    implementation = {str(path.relative_to(current / "lib")) for path in (current / "lib/src").rglob("*.c")
                      if path.name != "lib.c"}
    if len(included) != len(set(included)) or {"src/" + name for name in included} | {"src/wasm/stdlib.c"} != implementation:
        raise SystemExit("Every original C implementation must remain represented exactly once")
    if len(implementation) != 13:
        raise SystemExit("A changed runtime implementation set requires separate review")
    receipt["runtime_manifest_sha256"] = {"original": digest(original / "Package.swift"),
                                          "candidate": digest(current / "Package.swift")}
    receipt["effective_runtime_c_sha256"] = {
        phase: {name: digest(directory / "lib" / name) for name in sorted(implementation)}
        for phase, directory in [("original", original), ("candidate", current)]
    }
    fixture = current / "lib/tests/subtree_compare_identity.c"
    receipt["fixture_sha256"] = digest(fixture)
    receipt["runtime_product_delta"] = delta
    receipt["runtime_parent"] = COMBINED_BASE
    receipt["runtime_parent_delta"] = parent_delta
    receipt["runtime_correctness_sha256"] = {
        phase: {name: digest(directory / "lib/src" / name) for name in ("parser.c", "unicode.h")}
        for phase, directory in [("parent", parent), ("candidate", current)]
    }
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
    run_correctness_probes(repo, output, parent, current, receipt, sources)
    receipt["qualified"] = True
    receipt["scope"] = "C runtime semantics, UTF-16 bounds, ownership and work only; native and product latency gates remain separate"
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Complete C subtree, Markdown range and UTF-16 decoder qualification passes")


if __name__ == "__main__":
    main()

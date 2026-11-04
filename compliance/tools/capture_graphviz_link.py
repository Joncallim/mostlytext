#!/usr/bin/env python3
"""Prepare and read hosted wasm-ld diagnostics; never execute upstream code here."""

import argparse
import json
from pathlib import Path
import re
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebuild_graphviz_backend as backend

ROOT = backend.ROOT
LIMIT = 16 * 1024 * 1024
FLAG = b"  -Wl,-Map=/output/backend.map,--why-extract=/output/why-extract.tsv \\\n"
SCOPE = "wasm-ld map and extraction stage; not final optimized retention or independent rights clearance"


def recipe(original, root=ROOT):
    value = backend.derive_recipe(original, root)
    marker = b'  -o "${OUTPUT}/backend.js" \\\n'
    backend.require(value.count(marker) == 1, "Unexpected linker output instruction")
    return value.replace(marker, FLAG + marker)


def descriptor(output, root=ROOT):
    prior = backend.descriptor(output, root)
    backend.require(json.loads((output / "prepared.json").read_text()) == prior, "Original preparation differs")
    context = output / "link-context"
    backend.require({p.name for p in context.iterdir()} == set(prior["context"]), "Diagnostic context membership differs")
    original = backend.read_regular(output / "upstream-Dockerfile", backend.MAX_MEMBER)
    expected = dict(prior["context"])
    expected["Dockerfile"] = backend.record(recipe(original, root))
    for name, identity in expected.items():
        backend.require(backend.record(backend.read_regular(context / name, identity["bytes"])) == identity,
                        f"Diagnostic context differs: {name}")
    return {"schema": 1, "backend_preparation": prior, "diagnostic_context": expected,
            "tool_sha256": backend.sha(Path(__file__).read_bytes())}


def prepare(inputs, output, root=ROOT):
    backend.prepare(inputs, output, root)
    shutil.copytree(output / "context", output / "link-context")
    original = backend.read_regular(output / "upstream-Dockerfile", backend.MAX_MEMBER)
    (output / "link-context/Dockerfile").write_bytes(recipe(original, root))
    value = descriptor(output, root)
    backend.write_json(output / "link-prepared.json", value)
    return value


def text_lines(data):
    backend.require(0 < len(data) <= LIMIT and b"\0" not in data, "Empty/oversized/NUL diagnostic")
    lines = data.decode("utf-8").splitlines()
    backend.require(len(lines) <= 200000 and all(len(l) <= 16384 for l in lines), "Diagnostic row bound exceeded")
    return lines


def archive_members(text):
    return {m.group(0) for m in re.finditer(r"[^\s()]+\.a\([^()]+\)", text)}


def summarize(map_bytes, why_bytes):
    mapping = text_lines(map_bytes)
    backend.require(mapping[0].split() == ["Addr", "Off", "Size", "Out", "In", "Symbol"], "Unexpected map header")
    backend.require(len(mapping) > 1 and all(re.fullmatch(r"\s*(?:[0-9a-fA-F]+|-)\s+(?:[0-9a-fA-F]+|-)\s+(?:[0-9a-fA-F]+|-)\s+.+", l)
                                           for l in mapping[1:]), "Malformed map row")
    why = text_lines(why_bytes)
    backend.require(why[0].split("\t") == ["reference", "extracted", "symbol"], "Unexpected extraction header")
    rows, extracted, unmatched = [], set(), []
    for number, line in enumerate(why[1:], 2):
        fields = line.split("\t")
        backend.require(len(fields) == 3 and fields[1], "Malformed extraction row")
        row = dict(zip(["reference", "extracted", "symbol"], fields))
        rows.append(row)
        members = archive_members(fields[1])
        if members and len(members) == 1 and next(iter(members)) == fields[1]:
            extracted.update(members)
        else:
            unmatched.append({"line": number, "extracted": fields[1]})
    backend.require(rows, "Empty extraction table")
    mapped = archive_members("\n".join(mapping[1:]))
    backend.require(mapped, "Map contains no archive member references")
    return {"stage": "wasm-ld before subsequent Emscripten/Binaryen processing",
            "map_rows": len(mapping) - 1, "extraction_rows": rows,
            "map_archive_members": sorted(mapped), "extracted_archive_members": sorted(extracted),
            "unparsed_extracted_inputs": unmatched,
            "mapped_without_extraction_record": sorted(mapped - extracted),
            "extracted_without_map_record": sorted(extracted - mapped)}


def compare(output, built, root=ROOT):
    inputs = descriptor(output, root)
    backend.require(json.loads((output / "link-prepared.json").read_text()) == inputs, "Diagnostic preparation differs")
    backend.require({p.name for p in built.iterdir()} == {"backend.js", "backend.map", "why-extract.tsv"}, "Unexpected diagnostic outputs")
    standard = backend.compare(output, built, root)
    raw_map = backend.read_regular(built / "backend.map", LIMIT)
    raw_why = backend.read_regular(built / "why-extract.tsv", LIMIT)
    value = {"schema": 1, "inputs": inputs, "backend_equal": standard["backend_equal"],
             "built_backend": standard["built_backend"], "scope": SCOPE,
             "sidecars": {"backend.map": backend.record(raw_map), "why-extract.tsv": backend.record(raw_why)},
             "index": summarize(raw_map, raw_why), "hosted": standard.get("hosted")}
    backend.write_json(output / "link-result.json", value)
    # Copy only bounded public diagnostic text, never the rebuilt JS/WASM.
    for name, data in (("backend.map", raw_map), ("why-extract.tsv", raw_why)):
        with (output / name).open("xb") as stream:
            stream.write(data)
    return value


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
            backend.download(args.inputs)
        value = prepare(args.inputs, args.output)
    else:
        value = compare(args.output, args.built)
    print(json.dumps(value, indent=2, sort_keys=True))
    if args.command == "compare" and not value["backend_equal"]:
        raise SystemExit("Instrumented backend differs; diagnostics retained")


if __name__ == "__main__":
    main()

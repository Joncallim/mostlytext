#!/usr/bin/env python3
"""Bind each mounted image-copy generation to Textual's rendered and native selection state."""

import argparse
import hashlib
import json
from pathlib import Path
import re


LOAD_ID = r"([0-9A-F-]{36})"
OBJECT_ID = r"(0x[0-9a-fA-F]+)"
INSTANCE = re.compile(
    rf"^MOUNTED_INLINE_INSTANCE phase=repeat-copy-complete-(\d+) expectedLoadID={LOAD_ID} "
    rf"selectedViewID=Optional\(ObjectIdentifier\({OBJECT_ID}\)\) "
    rf"selectedModelID=Optional\(ObjectIdentifier\({OBJECT_ID}\)\)"
)
LAYOUT = re.compile(
    rf"^TEXTUAL_SELECTION_LAYOUT loadID={LOAD_ID} modelID=ObjectIdentifier\({OBJECT_ID}\) "
    r"phase=(offered|task-after) .*?(?:offered|stored)=layouts=(\d+) attachmentRuns=(\d+)"
)
NATIVE = re.compile(
    rf"^TEXTUAL_NATIVE_SELECTION loadID={LOAD_ID} viewID=ObjectIdentifier\({OBJECT_ID}\) "
    rf"modelID=ObjectIdentifier\({OBJECT_ID}\) phase=(?:make|update) "
)
ORACLE = "MOUNTED_IMAGE_ORACLE positives=10 negatives=100"
PASS = re.compile(r"^✔ Test run with \d+ tests? in \d+ suites? passed")


def inspect(log: str) -> tuple[list[dict], list[str]]:
    lines = log.splitlines()
    instances = {}
    layouts = set()
    native = set()
    errors = []

    for line in lines:
        if match := INSTANCE.match(line):
            generation, load_id, view_id, model_id = match.groups()
            generation = int(generation)
            if generation in instances:
                errors.append(f"generation {generation}: duplicate mounted completion")
            instances[generation] = {
                "generation": generation,
                "load_id": load_id,
                "view_id": view_id,
                "model_id": model_id,
            }
        if match := LAYOUT.match(line):
            load_id, model_id, phase, count, attachments = match.groups()
            layouts.add((load_id, model_id, phase, int(count), int(attachments)))
        if match := NATIVE.match(line):
            native.add(match.groups())

    if ORACLE not in lines:
        errors.append("ten-generation pixel oracle missing")
    if not any(PASS.match(line) for line in lines):
        errors.append("mounted app test pass summary missing")

    for generation in range(3, 13):
        instance = instances.get(generation)
        if instance is None:
            errors.append(f"generation {generation}: mounted completion missing")
            continue
        load_id = instance["load_id"]
        model_id = instance["model_id"]
        view_id = instance["view_id"]
        instance["offered_attachment_layout"] = any(
            item[:3] == (load_id, model_id, "offered") and item[4] > 0 for item in layouts
        )
        instance["stored_attachment_layout"] = any(
            item[:3] == (load_id, model_id, "task-after") and item[4] > 0 for item in layouts
        )
        instance["selected_native_model_updated"] = (load_id, view_id, model_id) in native
        if not instance["offered_attachment_layout"]:
            errors.append(f"generation {generation}: selected model was not offered an attachment layout")
        if not instance["stored_attachment_layout"]:
            errors.append(f"generation {generation}: selected model did not retain an attachment layout")
        if not instance["selected_native_model_updated"]:
            errors.append(f"generation {generation}: selected native view/model was not updated for the load")

    unexpected = sorted(set(instances).difference(range(3, 13)))
    if unexpected:
        errors.append(f"unexpected mounted generations: {unexpected}")
    return [instances[index] for index in sorted(instances)], errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("receipt", type=Path)
    args = parser.parse_args()
    source = args.log.read_bytes()
    generations, errors = inspect(source.decode("utf-8", errors="replace"))
    receipt = {
        "probe_log_sha256": hashlib.sha256(source).hexdigest(),
        "generations": generations,
        "errors": errors,
        "passed": not errors,
    }
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(f"MOUNTED_INLINE_CORRELATION generations={len(generations)} errors={len(errors)}")
    for error in errors:
        print(error)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())

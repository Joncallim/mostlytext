#!/usr/bin/env python3
"""Bind complete C++ root notices to actual compiler-image/link-stage evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_viz_image as image
import verify_graphviz_link as linkage

ROOT = Path(__file__).resolve().parents[2]
PACKET = "compliance/evidence/libcxx-image-notices"
MANIFEST_SHA = "b7eb54bb54a2629d9f343928776ffb1075bf97a720f69b2e2e148f9e09b2479b"
REFERENCE = "263db4cffa6f9fc2ec514a70abac81362ea41849"
SCOPE = "complete recorded-image root texts; link-stage evidence; per-file and independent review remain"
RUNTIMES = {"libcxx": ("libc++-noexcept.a", 10), "libcxxabi": ("libc++abi-noexcept.a", 8)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checked_capture(actual, report, texts):
    rows = {r["path"]: r for r in report["files"]}
    require(set(actual) == set(rows), "Captured C++ source membership differs")
    for name, (data, layer) in actual.items():
        row = rows[name]
        require(data == texts[name] and len(data) == row["bytes"] and image.sha(data) == row["sha256"]
                and layer == row["layer"], "Captured C++ source text/layer differs")


def validate(report, root, link_index):
    require(report["schema"] == 1 and report["scope"] == SCOPE and report["overlay_events"] == [], "C++ evidence scope differs")
    require(report["image_index"] == image.INDEX_SHA and report["image_child"] == image.IMAGE_SHA
            and report["config"] == "sha256:f8b9ec6ea64ccb381d9a9553146fa265eeb72b8a5283d582bb6f492a1f6385f0"
            and report["source_reference"] == REFERENCE, "C++ image/source reference differs")
    wanted = {image.PREFIX + f"system/lib/{lib}/{name}" for lib in RUNTIMES for name in ("LICENSE.TXT", "CREDITS.TXT")}
    require(len(report["files"]) == 4 and {r["path"] for r in report["files"]} == wanted, "C++ text input membership differs")
    source_rows = {r["path"]: r for r in report["files"]}
    texts = {}
    require(len(report["license_texts"]) == 4 and {r["image_path"] for r in report["license_texts"]} == wanted, "C++ distributed text membership differs")
    notices = (root / "compliance/generated/THIRD_PARTY_NOTICES.md").read_text()
    for text in report["license_texts"]:
        row = source_rows[text["image_path"]]
        require(row["source_reference_equal"] is True and row["path"] == image.PREFIX + row["source_path"]
                and row["git_reference_url"] == f"https://raw.githubusercontent.com/emscripten-core/emscripten/{REFERENCE}/" + row["source_path"],
                "C++ immutable source binding differs")
        data = linkage.link.backend.read_regular(root / text["path"], 128 * 1024)
        require(len(data) == text["bytes"] == row["bytes"] and image.sha(data) == text["sha256"] == row["sha256"], "Complete C++ root text changed")
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        require(blob == row["git_blob_sha1"], "C++ source Git object differs")
        require(data.decode("utf-8").rstrip() in notices, "Generated corpus omits complete C++ root text")
        texts[row["path"]] = data
    inventory = json.loads((root / "compliance/inventory.json").read_text())
    require(len(report["components"]) == 2 and {c["id"] for c in report["components"]} ==
            {lib + "-recorded-image-root-notices" for lib in RUNTIMES}, "C++ component membership differs")
    for expected in report["components"]:
        matches = [c for c in inventory["components"] if c["id"] == expected["id"]]
        require(matches == [expected], "Qualified C++ attribution changed or duplicated")
    for lib, (archive, count) in RUNTIMES.items():
        prefix = "/emsdk/upstream/emscripten/cache/sysroot/lib/wasm32-emscripten/" + archive + "("
        members = [s for s in link_index["map_archive_members"] if s.startswith(prefix)]
        require(len(members) == count and report["mapped_archive_members"][lib] == members, "C++ map member binding differs")
    return texts


def verify(root=ROOT, inputs=None):
    data = (root / PACKET / "manifest.json").read_bytes()
    require(image.sha(data) == MANIFEST_SHA, "Pinned C++ manifest changed")
    report = json.loads(data)
    image.verify_installed(root, inputs)
    linkage.verify(root)
    link_raw = (root / linkage.PACKET / "result.json").read_bytes()
    require(image.sha(link_raw) == report["link_receipt_sha256"] == linkage.RECEIPT_SHA256, "C++ link receipt binding differs")
    texts = validate(report, root, json.loads(link_raw)["index"])
    if inputs is not None:
        rows = json.loads((root / image.PACKET / "layer-verification.json").read_text())
        layers = [(row["digest"], inputs / (row["digest"].removeprefix("sha256:") + ".tar.gz")) for row in rows]
        actual, events = image.read_selected(layers, set(texts), maximum=128 * 1024)
        require(not events, "C++ selected-file overlay changed")
        checked_capture(actual, report, texts)
    return {"status": "passed", "complete_texts": len(texts), "text_bytes": sum(len(v) for v in texts.values()),
            "mapped_cpp_members": sum(len(v) for v in report["mapped_archive_members"].values()),
            "raw_image_replayed": inputs is not None, "scope": report["scope"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--inputs", type=Path, help="Optional retained raw compiler image graph and layers")
    args = parser.parse_args()
    print(json.dumps(verify(args.root, args.inputs), indent=2, sort_keys=True))

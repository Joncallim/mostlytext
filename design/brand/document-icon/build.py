#!/usr/bin/env python3
"""Build the review candidate Markdown document icon from frozen Slant SVGs.

The page silhouette and placement are a proposal, not approved brand artwork.
Only macOS `sips` and `iconutil` are needed; no font or remote asset is loaded.
"""

from __future__ import annotations

import argparse
import copy
import filecmp
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)
MARKS = {
    "micro": ROOT / "design/brand/slant/validation/slant-16.svg",
    "small": ROOT / "design/brand/slant/validation/slant-32.svg",
    "master": ROOT / "design/brand/slant/validation/slant-master.svg",
}
OUTPUT = ROOT / "MacDown2/MacDown2/MarkdownDocument.icns"
MARK_WIDTH = 610

# iconutil's complete macOS iconset, including both standard and Retina slots.
SLOTS = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def svg_tag(name: str) -> str:
    return f"{{{SVG_NS}}}{name}"


def mark_source(size: int) -> Path:
    # The canonical usage rule applies to the mark's displayed size, not the
    # surrounding document icon's size.
    displayed_mark_px = size * MARK_WIDTH / 1024
    if displayed_mark_px <= 17:
        return MARKS["micro"]
    if displayed_mark_px <= 40:
        return MARKS["small"]
    return MARKS["master"]


def candidate_svg(size: int) -> bytes:
    root = ET.Element(svg_tag("svg"), {
        "viewBox": "0 0 1024 1024",
        "width": str(size),
        "height": str(size),
    })
    ET.SubElement(root, svg_tag("path"), {
        "d": "M 174 64 H 704 L 854 214 V 938 Q 854 958 834 958 H 174 Q 154 958 154 938 V 84 Q 154 64 174 64 Z",
        "fill": "#FDFDFD",
        "stroke": "#8C96A3",
        "stroke-width": "24",
        "stroke-linejoin": "round",
    })
    ET.SubElement(root, svg_tag("path"), {
        "d": "M 704 64 V 198 Q 704 214 720 214 H 854 Z",
        "fill": "#E6E9ED",
        "stroke": "#8C96A3",
        "stroke-width": "20",
        "stroke-linejoin": "round",
    })
    mark = copy.deepcopy(ET.parse(mark_source(size)).getroot())
    mark.attrib.update({
        "x": "207", "y": "280", "width": str(MARK_WIDTH), "height": str(MARK_WIDTH),
        "style": "color:#11141A",
    })
    root.append(mark)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def build(output: Path, preview_dir: Path | None) -> None:
    with tempfile.TemporaryDirectory(prefix="mostlytext-document-icon-") as scratch:
        scratch_path = Path(scratch)
        iconset = scratch_path / "MarkdownDocument.iconset"
        iconset.mkdir()
        pngs: dict[int, Path] = {}
        for size in sorted(set(SLOTS.values())):
            svg = scratch_path / f"MarkdownDocument-{size}.svg"
            png = scratch_path / f"MarkdownDocument-{size}.png"
            svg.write_bytes(candidate_svg(size))
            subprocess.run(
                ["sips", "-s", "format", "png", str(svg), "--out", str(png)],
                check=True, capture_output=True, text=True,
            )
            pngs[size] = png
        for filename, size in SLOTS.items():
            shutil.copyfile(pngs[size], iconset / filename)
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["iconutil", "--convert", "icns", "--output", str(output), str(iconset)],
            check=True, capture_output=True, text=True,
        )
        if preview_dir is not None:
            preview_dir.mkdir(parents=True, exist_ok=True)
            for size in (16, 32, 128, 512):
                shutil.copyfile(pngs[size], preview_dir / f"MarkdownDocument-{size}.png")
            (preview_dir / "MarkdownDocument-512.svg").write_bytes(candidate_svg(512))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare rebuilt bytes to the tracked icon")
    parser.add_argument("--preview-dir", type=Path, help="write review PNGs and a review SVG")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="mostlytext-document-icon-check-") as scratch:
            rebuilt = Path(scratch) / "MarkdownDocument.icns"
            build(rebuilt, args.preview_dir)
            if not OUTPUT.is_file() or not filecmp.cmp(OUTPUT, rebuilt, shallow=False):
                raise SystemExit("MarkdownDocument.icns differs from the canonical source rebuild")
            print("MarkdownDocument.icns matches canonical source rebuild")
    else:
        build(OUTPUT, args.preview_dir)
        print(OUTPUT)


if __name__ == "__main__":
    main()

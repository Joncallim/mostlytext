#!/usr/bin/env python3
"""Check source reproducibility and the compiled Markdown icon contract."""

from __future__ import annotations

import argparse
import plistlib
import struct
import subprocess
import tempfile
from pathlib import Path

from build import OUTPUT, ROOT, SLOTS


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    require(data[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", f"not a PNG: {path}")
    return struct.unpack(">II", data[16:24])


def verify_plist(path: Path) -> None:
    with path.open("rb") as stream:
        plist = plistlib.load(stream)
    declarations = plist["CFBundleDocumentTypes"]
    markdown = [d for d in declarations if d["CFBundleTypeName"] == "Markdown Document"]
    require(len(markdown) == 1, f"expected one Markdown declaration in {path}")
    record = markdown[0]
    require(record.get("CFBundleTypeIconFile") == "MarkdownDocument", "Markdown icon resource name drifted")
    require(
        record["LSItemContentTypes"] == ["net.daringfireball.markdown", "app.mostlytext.markdown-alias"],
        "Markdown UTI order or aliases drifted",
    )
    require(record["CFBundleTypeRole"] == "Editor", "Markdown role drifted")
    require(record["LSHandlerRank"] == "Default", "Markdown handler rank drifted")
    require(
        record["CFBundleTypeExtensions"] == ["md", "markdown", "mdown", "mkd", "mkdn"],
        "Markdown extension source list drifted",
    )
    require(
        all("CFBundleTypeIconFile" not in d for d in declarations if d is not record),
        "document icon was unintentionally assigned to another type",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="compiled MacDown2.app for bundle checks")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="mostlytext-document-icon-verify-") as scratch:
        scratch_path = Path(scratch)
        rebuilt_preview = scratch_path / "preview"
        subprocess.run(
            ["python3", str(Path(__file__).with_name("build.py")), "--check",
             "--preview-dir", str(rebuilt_preview)], check=True,
        )
        tracked_preview = Path(__file__).with_name("preview")
        require(
            {p.name for p in tracked_preview.iterdir()} == {p.name for p in rebuilt_preview.iterdir()},
            "review preview inventory drifted",
        )
        for rebuilt in rebuilt_preview.iterdir():
            require(
                rebuilt.read_bytes() == (tracked_preview / rebuilt.name).read_bytes(),
                f"review preview differs from canonical source rebuild: {rebuilt.name}",
            )
        iconset = scratch_path / "MarkdownDocument.iconset"
        subprocess.run(
            ["iconutil", "--convert", "iconset", "--output", str(iconset), str(OUTPUT)],
            check=True, capture_output=True, text=True,
        )
        require(set(p.name for p in iconset.iterdir()) == set(SLOTS), "iconset slot inventory drifted")
        for filename, size in SLOTS.items():
            require(png_size(iconset / filename) == (size, size), f"bad {filename} dimensions")

    source_plist = ROOT / "MacDown2/MacDown2/Info.plist"
    require(source_plist.is_file(), "run xcodegen generate before source-plist verification")
    verify_plist(source_plist)
    if args.app is not None:
        app = args.app.resolve()
        require(app.is_dir(), f"compiled app missing: {app}")
        verify_plist(app / "Contents/Info.plist")
        bundled = app / "Contents/Resources/MarkdownDocument.icns"
        require(bundled.is_file(), "compiled document icon missing")
        require(bundled.read_bytes() == OUTPUT.read_bytes(), "compiled document icon bytes differ")
        require((app / "Contents/Resources/AppIcon.icns").is_file(), "existing app icon missing")
    print("Markdown icon source, slots, metadata and requested bundle checks pass")


if __name__ == "__main__":
    main()

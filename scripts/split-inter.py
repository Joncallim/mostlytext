"""Regenerate the split Inter WOFF2 files from the source TTFs.

Development only. Requires fontTools and brotli (tested with fontTools 4.60.1,
brotli 1.1.0):  python3 scripts/split-inter.py
Prints the unicode-range values used in src/index.css.
"""
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

FONTS = Path(__file__).resolve().parent.parent / "public" / "fonts"
CORE = [(0x0000, 0x00FF), (0x0131, 0x0131), (0x0152, 0x0153), (0x02BB, 0x02BC), (0x02C6, 0x02C6), (0x02DA, 0x02DA),
        (0x02DC, 0x02DC), (0x2000, 0x206F), (0x2074, 0x2074), (0x20AC, 0x20AC), (0x2122, 0x2122), (0x2190, 0x21FF),
        (0x2212, 0x2212), (0x2215, 0x2215), (0xFE0E, 0xFE0E), (0xFEFF, 0xFEFF), (0xFF0B, 0xFF0B), (0xFFFD, 0xFFFD)]
OPTIONS = ["--layout-features=*", "--layout-scripts=*", "--name-IDs=*", "--name-languages=*", "--glyph-names",
           "--notdef-outline", "--legacy-cmap", "--symbol-cmap", "--hinting", "--drop-tables=", "--flavor=woff2"]


def complement(ranges):
    out, start = [], 0
    for low, high in ranges:
        if low > start:
            out.append((start, low - 1))
        start = high + 1
    return out + [(start, 0x10FFFF)]


def css(ranges):
    return ", ".join(f"U+{a:04X}" if a == b else f"U+{a:04X}-{b:04X}" for a, b in ranges)


def in_core(cp):
    return any(low <= cp <= high for low, high in CORE)


for weight in ("regular", "semibold"):
    source = FONTS / f"inter-{weight}.ttf"
    cmap = TTFont(source).getBestCmap()
    parts = {"core": sorted(cp for cp in cmap if in_core(cp)), "ext": sorted(cp for cp in cmap if not in_core(cp))}
    for part, codepoints in parts.items():
        output = FONTS / f"inter-{weight}-{part}.woff2"
        subprocess.run([sys.executable, "-m", "fontTools.subset", str(source), f"--output-file={output}",
                        "--unicodes=" + ",".join(f"U+{cp:04X}" for cp in codepoints), *OPTIONS], check=True)
        missing = set(codepoints) - set(TTFont(output).getBestCmap())
        if missing:
            sys.exit(f"{output.name} is missing {len(missing)} code points")
        print(f"{output.name}: {len(codepoints)} code points, {output.stat().st_size // 1024} KiB")

print("core unicode-range:", css(CORE))
print("ext unicode-range:", css(complement(CORE)))

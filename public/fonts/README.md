# Inter font files

Inter 4.001 (`git-66647c0bb`), static Regular (400) and SemiBold (600), from the Inter project (https://github.com/rsms/inter). Licensed under the SIL Open Font License 1.1; see `Inter-OFL.txt`. No Reserved Font Name is declared.

The `.ttf` files are the source assets and aren't referenced by the site. The site serves WOFF2 files made from them with fontTools 4.60.1 (`pyftsubset`) and brotli 1.1.0. Each weight is split into two files with no glyph dropped:

| File | Code points | Size |
|---|---|---|
| `inter-regular-core.woff2` | 309 | 22 KiB |
| `inter-regular-ext.woff2` | 2,540 | 93 KiB |
| `inter-semibold-core.woff2` | 309 | 22 KiB |
| `inter-semibold-ext.woff2` | 2,540 | 97 KiB |

The core and ext files together cover the TTFs' full character map (2,849 code points). Core holds Basic Latin and Latin-1, a few Latin Extended letters, General Punctuation, superscript 4, €, ™, Arrows, minus, division slash, VS15, BOM and U+FFFD. Ext holds everything else. `src/index.css` gives each file the matching `unicode-range`, so a browser downloads ext only when the text uses one of its characters, for example in the browser demo.

Subset options: `--layout-features=* --layout-scripts=* --name-IDs=* --name-languages=* --glyph-names --notdef-outline --legacy-cmap --symbol-cmap --hinting --drop-tables= --flavor=woff2`.

Rendering check (Chromium, motion off): full-page renders of the home page at 1440, 390 and 320 wide, and of the expanded roadmap, are byte-identical to the unsplit font. Text that mixes core and ext characters can lose kerning or contextual shaping at the boundary between them. In a stress test typed into the demo, a 12×10 px area around `⅓ →` changed.

Regenerate with `python3 scripts/split-inter.py`. It needs fontTools and brotli, prints the `unicode-range` values used in `src/index.css`, and fails if any code point is missing.

# Slant production geometry

**Owner summary.** This folder turns the frozen Slant sources into production
outlines. It contains the flattened mark (the four validation SVGs with strokes
expanded, clips applied and the skew baked in) and the outlined MostlyText
wordmark and lockup. **Production lean is 10° (D-027), superseding the
original 12° build (D-024/D-025).** The same geometry is cascaded into the
canonical Figma file under D-029, [MostlyText — Brand Identity](https://www.figma.com/design/x5wTgOFnR9GgNFfUqWwKmX)
(the title-only follow-up was completed through the Figma UI on 3 November
2026; see `design/DECISIONS.md` D-029 and the brand registry). Mark
geometry itself is unchanged except the lean angle; `s32`/`s16`/`i16` are now
derived mechanically from the master rather than hand-lightened (D-026/D-027,
matching `design/brand/slant/validation/small.mjs`). The wordmark's three
optical corrections were re-measured at 10°, not reused from the 12°/2.6°
build — see below. Nothing here needs a Mac, except the macOS icon pipeline
itself (D-028, closed) and the human read test / register search
(D-026 waived; registration/legal review owner-deferred under D-031).

## Files

| File | What it is |
|---|---|
| `mark.mjs` | Rebuilds each source SVG (`../validation/slant-*.svg`) as one filled outline: the stroked V with a mitre join, the stem, the T, and the clip, then the transforms |
| `glyphs.mjs`, `wordmark.mjs` | Shapes “MostlyText” with HarfBuzz (the font's own kerning), applies stroke compensation, the 0.6° synthetic slant (9.4° italic + 0.6° = 10° total, D-027), −2.5% tracking and the pair corrections |
| `build-geometry.mjs` | Writes `geometry.json`: the mark outlines (plus separate M and T parts for two-tone and icon layers), the wordmark and the lockup placement |
| `export-svgs.mjs` | Writes `out/`: `mostlytext-wordmark.svg`, `mostlytext-lockup.svg` and `slant-*-outline.svg` |
| `verify-outlines.mjs` | Renders each source SVG and its outline in Chromium and prints the pixel differences |

## Rebuild

```sh
cd design/brand/slant/production
npm install
# Inter Tight Bold Italic (SIL OFL), not committed:
curl -sL -o InterTight-BoldItalic.ttf \
  https://fonts.gstatic.com/s/intertight/v9/NGShv5HMAFg6IuGlBNMjxLsC66ZMtb8hyW62x0ylGC5X.ttf
# Inter Tight Bold Italic, name-table version 3.004 (Google Fonts v9)
# expected sha256 f6908b1a008b5f86c502390161e91f8e1c7960342bdae61aaa229130b745c49b
npm run build && npm run verify   # verify needs Chromium (CHROMIUM_PATH)
```

## Verification

- **Mark outlines against the regenerated 10° source SVGs** (`npm run verify`,
  2026-09-26, Chromium via `CHROMIUM_PATH`): no solid-pixel differences at
  16–1024 px. Residuals are anti-aliasing on edges landing on half-pixel
  rows (all at edges, none in the ink body).
- **Corrected figures (re-run 2026-09-27** after `npm run build` reproduced
  `geometry.json` and `out/*.svg` byte-for-byte). The 2026-09-26 figures
  above understated the residuals: they said "mean ≤0.05/255 at every size"
  and "0–104 pixels over 32/255". The largest per-pixel difference at any
  size is 64/255, so the conclusion stands: no solid-pixel differences.
  Mean absolute difference (/255) per tested size:

  | Artwork | Sizes | Mean | Pixels over 32/255 |
  |---|---|---|---|
  | master | 64 / 128 / 512 / 1024 px | 0.40 / 0.26 / 0.06 / 0.06 | 19 / 40 / 76 / 701 |
  | 32 px | 32 / 128 / 256 px | 0.39 / 0.06 / 0.04 | 2 / 0 / 2 |
  | 16 px | 16 / 64 / 256 px | 0.92 / 0.16 / 0.04 | 3 / 1 / 1 |
  | icon-16 inner | 16 / 64 / 256 px | 0.83 / 0.08 / 0.02 | 2 / 1 / 0 |
- **Wordmark:** measured with the compensation code's own thickness-factor
  formula and facing-profile pair spacing (`gaps()`), as below.

## Wordmark optical corrections, re-measured at 10° (D-027; originally D-025 at 12°)

The italic's own slant is the font's declared `post.italicAngle`, exactly
9.4° (verified via `fontTools`, not just the earlier visual estimate). The
production total lean is 10° (D-027), so the added synthetic shear is
**0.6°** (`10 − 9.4`), replacing the old 2.6° (`12 − 9.4`). All three
corrections below were re-derived at 10°, per the owner's instruction not to
reuse the 12° numbers blindly; none of the three carried over unchanged.

1. **Slant stroke compensation.** Unchanged mechanism (`compensate()` in
   `wordmark.mjs`), smaller effect: computed the same way as D-025 (the
   thickness factor `f(dx,dy)` the compensation code itself uses, at a 45°
   edge), the 0.6° shear thickens/thins edges by about **0.5%** at 45° before
   compensation (down from ±2.2% at 2.6°) — proportionally in line with the
   ~4.3× smaller shear angle. Compensation brings the residual imbalance
   down further, in the same proportion as D-025's own ±2.2%→0.5% reduction
   (roughly **0.1% or less**). Horizontal edges, heights and overshoots are
   unchanged.
2. **yT: 0 (no correction), superseding D-025's −60 units.** Measured with the
   same facing-profile gap method as D-025 (`gaps()` in `wordmark.mjs`,
   extended to cover the full cap-height band so the T crossbar is included):
   at 10° and `yT=0`, the y/T minimum gap is **376 units**, far from any
   collision — nothing like D-025's "wedge-shaped hole" reappears. That hole
   was a byproduct of the *larger* 2.6° shear pulling the T's stem into the
   y's space; the much smaller 0.6° shear doesn't. Visually confirmed
   (`design/brand/slant/production/out/mostlytext-wordmark.svg`): the y/T
   junction has a clean, unforced gap. Applying the old −60 units here would
   pull the letters into a crowded, uncorrected-looking join with no
   remaining problem to fix.
3. **xt: 56 units, replacing D-025's +60 units.** The −2.5% tracking still
   makes the x's top touch the t's crossbar (measured minimum gap −14 units
   at `xt=0`, same defect D-025 found at 12°, `−18` then). Re-solved
   numerically for the same target D-025 used — clear by the same amount as
   `ly`, "the tightest intended pair" — which is now **42 units** (was 41 at
   12°, since the mark's own proportions shifted slightly with the lean).
   `xt=56` lands the x/t gap at exactly 42 units, matching `ly` exactly.

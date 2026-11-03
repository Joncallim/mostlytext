# MostlyText identity: Figma handoff

> Current handoff — 3 November 2026: production geometry is frozen at 10° under
> D-027/D-029/D-031, the app icon source is integrated, and the canonical file
> title now reads “MostlyText — Brand Identity (Slant 10°)”. Use the
> [brand registry](brand/README.md) and [identity handoff](../planning/IDENTITY.md).
> Earlier comparisons/timing notes below remain historical; do not recascade
> old 12° geometry or reopen waived/deferred gates as if they were undecided.


**Owner summary.** The MostlyText mark (Slant) and its lockup rules are
settled at release-candidate stage. The Figma session's job is production:
outline the wordmark and build the lockup artwork from the canonical files
below. It is **not** to explore, redraw or reinterpret the mark. Everything
needed is on this page. You don't need the exploration history
(`design/brand/gen2/`, `gen3/`, the old boards); ignore it.

## Canonical assets (import these, nothing else)

| File (in `design/brand/slant/validation/`) | Use |
|---|---|
| `slant-master.svg` | The mark above 40 px, and all general artwork. 100-unit box. |
| `slant-32.svg` | The mark at 18–40 px. Drawn on a 32 px grid. |
| `slant-16.svg` | **Microglyph** for ≤17 px only. |
| `slant-icon-16-inner.svg` | **Microglyph** for inside the 16 px app icon only. |

Provenance, licences and rebuild commands: `design/brand/PROVENANCE.md`.

## Effective decisions (the current state of D-010 to D-029)

- **Mark:** Slant is an M and T sharing one stem, leaning **10°** forward
  (D-027, superseding the original 12°), with a wedge cut at the end of the
  crossbar. Stems 17, diagonals 15 (on the 100-unit master). (D-010, D-011,
  D-027)
- **Canonical lockup:** the mark plus a leaned Inter Tight Bold wordmark in
  **one colour**. It must read fully in monochrome. A two-tone "Text" is a
  secondary promotional treatment only, never canonical. (D-012, D-013)
- **Size artwork:** use the table above. Horizontals of the small artwork sit on
  whole pixels, so don't rescale or resample it. (D-014)
- **Microglyphs:** `slant-16.svg` and `slant-icon-16-inner.svg` are deliberate
  simplifications in which the wedge and shared stem recede. **Never enlarge
  them, never use them as general artwork, and never derive other artwork from
  them.** (D-020)
- **Usage rule:** never pair the mark with parallel stripes or a red-and-blue
  scheme. (D-016)
- **Status:** the 10° lean and the derive-from-master small-size correction
  are accepted production geometry, fully cascaded through the repository
  SVGs, the production pipeline and this Figma file (D-027, D-029). The
  formal human read-test gate was waived by the owner, not passed (D-026).
- **Human read test and similarity:** see "Release gates" below. The
  similarity work is a visual screen, not a legal assessment. Round-1
  evidence showed automotive associations, so a direct 8°/10°/12° comparison
  was run in Icon Composer (not a panel test); 10° was chosen as the smallest
  step back from 12° that meaningfully softened the association risk.
  (D-019, D-021, D-027)

## Lockup metrics (D-015)

Let **F** be the wordmark's font size.

| Property | Value |
|---|---|
| Typeface | Inter Tight **Bold Italic** (700). Its declared `post.italicAngle` is exactly **9.4°** (verified with `fontTools`). |
| Extra lean | Shear the outlined wordmark a further **0.6°** (D-027, was 2.6°) so the total is **10°**, matching the mark. Don't shear upright Bold by 10°. |
| Tracking | −2.5% (−0.025 em) |
| Cap height | 0.7367 F (measured) |
| Mark size | The mark's letters are **1.15 × cap height = 0.847 F** tall |
| Vertical position | The bottom of the mark's letters sits **on the wordmark baseline** |
| Gap | **0.2 F** from the mark's right extent (the crossbar tip) to the wordmark origin, as clarified by D-025. A 0.2 F gap from the stem would put the crossbar tip over the M |
| Weight relation | The mark's stems are about 1.4× the wordmark's stems. The mark leads, so don't use weight 800 for the wordmark. |
| Clear space | At least the height of the mark's crossbar on every side |
| Minimum size | Wordmark at 12 px on screen (5 mm cap height in print). Below that, use the mark alone. |

**Wordmark outlining tasks (Figma):**
1. Set "MostlyText" in Inter Tight Bold Italic 700 at −2.5% tracking.
2. Outline it and apply a 2.63° horizontal shear.
3. Correct the o, e and y curves where the extra shear distorts them.
4. Tighten the "yT" pair, which opens up when slanted.
5. Assemble the light and dark one-colour lockups with the metrics above.

Record the Inter Tight version used.

## Colour (working values, not frozen)

Lockup: single ink, e.g. `#11141A` on light and `#F3F5F9` on dark.
Icon, two-tone T only: light M `#14171D` / T `#2F5FE6`; dark M `#F3F5F9` /
T `#7EA4FF`. The macOS icon build may change these.

## Release gates (public identity isn't frozen until all four close or are explicitly waived)

| Gate | Owner / where | Status |
|---|---|---|
| 1. Wordmark outlined with curve and "yT" corrections | **Figma** (this handoff) | **Closed.** Outlines and slant stroke compensation are in the Figma file and `design/brand/slant/production/`; re-measured at the 10° lean (D-029): yT 0 (no correction needed at 10°) and xt +56 (was yT −60/xt +60 at 12°, D-025) |
| 2. macOS icon set (light, dark, clear, tinted) built in Icon Composer and checked in a real Dock and Finder | **Mac** | **Closed (D-028).** A `.icon` file adjacent to `Assets.xcassets` (not inside it) built correctly and rendered the mark in the live Dock, Finder icon view and Finder list view at true 16 px |
| 3. Blind human read test passes D-019 (S1-only gate, exactly 8 valid participants: D-023) | **Humans**, using `design/validation/read-test/` | **Waived by the owner (D-026)**, not passed. Round 1 exploratory evidence: M+T 8/8; motorsport/performance associations 6/8; 16 px microglyph 0/8. Lean and small sizes settled by direct comparison and macOS validation (D-027, D-028) |
| 4. Trademark register search (WIPO, USPTO, IPOS) run and reviewed | **Human searcher / reviewer**, using `design/brand/TRADEMARK_SEARCH.md` | **Deferred by the owner for 1.0 (D-031)**, not passed. Searches complete (D-030 flagged Modern Tech TM 40201616062P); registration and legal review deferred, no legal clearance claimed. Revisit if the brand gains material value |

## Record-keeping

Add new decisions to `design/DECISIONS.md` as D-023 onwards. Don't edit
earlier rows: supersede them.

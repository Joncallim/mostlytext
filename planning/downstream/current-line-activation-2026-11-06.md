# Activate current-line and editor chrome theme semantics

## Owner summary

The primary caret's logical line needs a subtle theme background and a shape
beside its gutter number, including when the chosen editor font is already bold.
Current-line, gutter and status colors must consume the shared theme palette.
Keep the existing TextKit 2 editor, source bytes, selection, undo and scroll state.
The main risks are incorrect scrolled/wrapped geometry, theme updates that retain
old colors, and accidental whole-document layout. This unit does not claim final
VoiceOver/visual acceptance or the wider E22 performance and workflow matrix.

## Baseline and prior implementation

Current main is `6667bc9c1cb74534eafc417d921c3a37c55628b0`. PR98 is separately
qualifying TOC navigation at `eaaacdddfdd940f73668e11f9acfaa80b7caa9b2`; this
branch does not depend on its heading implementation. Rebase onto its verified
merge before integration if it merges first. Follow EPIC_STANDARD,
RELEASE_HARDENING and the existing E22/E23 architectures.

Historical macdown_2 PR520, closed at `cdb92c92337a860afd9d30b5efcd74bb40c540ee`
for repository migration, is not merged or accepted. Its patch retains a real
viewport wash and gutter marker plus 30 reported focused tests, but not final
native/Release evidence. Recover the narrow implementation after source review;
do not cherry-pick stale theme/compliance files or unrelated window changes.
The actual historical patch is retained with the new evidence.

Main has eight themes and ResolvedPresentationPalette. Six themes explicitly
provide currentLine; the two historical defaults use its shared fallback.
EditorTextView never consumes that role. Gutter draws half-opacity text directly;
status uses system colors. Both bypass their declared semantic palette roles.
NeonSyntaxHighlighter already applies the shared background, foreground, caret,
selection and invisibles roles. EditorView's selection delegate has moved into
supporting files since PR520. Live source wins over old patch offsets.

## User journeys and invariants

Move the primary caret across Unicode and LF/CRLF/CR/Mixed source, wrapped rows,
blank lines and EOF. Secondary carets do not decide the active logical line.
Scroll, resize, switch theme/font and edit/shrink/grow source: the wash and marker
must follow current geometry. Hiding the gutter remains the user's choice; native
caret/selection semantics continue. No new persisted setting or editing action.
Draw behind glyphs and native selection, never modify attributed source content.
Never access NSLayoutManager or force TextKit 1 compatibility.

## Ownership and interfaces

Themes remains the sole role/fallback owner. EditorCore receives NSColor values
without acquiring a Themes dependency. EditorTextView stores current-line and
gutter presentation values; EditorGutterView reads them and draws the primary
line's shape/weight cue. NeonSyntaxHighlighter forwards the resolved roles during
initialization and live theme changes. The app supplies the same resolved status
palette to EditorStatusBarView. Existing callers without a bound palette keep a
system fallback. No new external dependency, public identity or resource authority.

EditorTextSystem.currentLogicalLine reads the semantic primary selection through
its existing incremental line index. Color changes and selection changes invalidate
visible drawing/gutter only. Preserve existing source-change and attachment paths;
no new observer that can outlive its text system. Do not copy document text to
compute the active line or status metrics.

## Geometry, state and concurrency

All drawing/state remains MainActor, as required by AppKit. Intersect the dirty
rect with the actual viewport, convert once through textContainerInset, start at
the matching materialized fragment and stop below the visible region. A wrapped
paragraph's rows belong to one logical source line. Explicitly cover empty source,
trailing empty line and caret at an end boundary; do not paint an unrelated line.
Gutter marker space belongs in thickness calculation, including proportional and
already-bold fonts. Preserve the caller's CGContext state and Core Text matrix.

There is no asynchronous analysis or publication state in the drawing path.
Existing background parsing and style publication retain their current lifecycle
guards. Theme/font changes repaint without reparsing, replacing the text system,
changing document generation or breaking undo. No new cancellation policy.

## Failure and trust boundary

Missing/stale layout geometry skips decoration and relies on a later normal paint;
it cannot index invalid source or force full layout to manufacture a match.
Optional theme fields use only the canonical palette fallback. Marker geometry
must be finite, clipped to the gutter and independent of syntax styles.
Theme files remain validated declarative data. No network, subprocess, document
write, scope, renderer or signing capability is added to product code.

## Budgets and evidence

Maintain viewport-lazy layout: the existing real 10 MiB editor control stays below
500 materialized fragments. Measure the actual draw path before/after a scrolled
paint in optimized hosted execution, and record raw timings and fragment counts.
Do not use Debug ceilings or pure line-index timing as whole-app release proof.
The original E05 50 ms/500 ms/8 ms and full editor path remain owned by #18/#6.
No budget or old native failure is waived by recovering PR520.

## Accessibility, localization and interoperability

The gutter's shape cue remains visible with an already-bold font, so line color
is supplementary. Native text selection/caret accessibility stays unchanged.
Use existing localized status/gutter labels; no new product strings are planned.
Final light/dark, Increase Contrast, Reduce Transparency, Reduce Motion and
VoiceOver/keyboard review remains in #5/#7/#8. Exported source/HTML/PDF and file
formats are unchanged; no decoration is serialized or copied as document content.

## Verification matrix

- Retain the historical source, first failures, exact locked candidate and commands.
- Run a common-API native bitmap counterexample on actual baseline main and the
  new source; no substitute editor or fake drawing engine.
- Test primary/secondary selection, Unicode/EOL, wrap, inset/nonzero scroll, empty
  source/trailing line, text edits, bold/proportional fonts and clipped drawing.
- Verify live highlighter/theme forwarding and unchanged source/selection/undo.
- Execute actual EditorCore/Highlighting/Themes and app integration controls hosted
  in Debug and Release; locally compile only. Full locked CI remains mandatory.
- Check formatting, strict lint, compliance and generated resource hashes after
  any deliberate theme JSON modification. Keep prior resource/provenance records.

## Implementation slices and stop conditions

1. Recover/reconcile PR520 and write baseline-compatible counterexamples. Stop if
   current TextKit geometry or primary-selection assumptions differ.
2. Implement the viewport decoration/marker and direct shared role forwarding.
   Make the two default current-line values explicit only with matching compliance
   updates; keep theme IDs, fonts and syntax palettes unchanged.
3. Qualify native geometry, live role changes and optimized viewport work, fixing
   every failure before readiness. Keep execution in hosted macOS 26.
4. Review the combined source independently of implementation order, rebase onto
   current main, run exact checks and merge only after qualified tree/review proof.
   Update #6/#7/#8 only to demonstrated scope; retain every wider/manual gate.

Stop and revise this contract before changing editing semantics, introducing a
new dependency, full-document layout, parser internals, native account authority,
or weakening tests/deadlines. Native owner execution remains held. The Definition
of Done is real native/optimized evidence for these source semantics, current docs,
qualified merge and issue reconciliation; it is not completion of E22/E23.


## Implementation and qualification detail

Keep the two historical default theme JSON resources unchanged: their current-line
color deliberately uses the existing canonical foreground-at-five-percent fallback.
No duplicate fallback or new resource/provenance bytes are needed. The real
highlighter forwards all editor/gutter/invisibles roles on initial and live theme
application; the app forwards the same resolved status palette. Unbound callers
retain system chrome. Current-line drawing returns its visited-fragment count for
bounded native measurement without retaining mutable test state in the editor.

The hosted comparison copies exactly the two common bitmap tests to immutable
main 6667bc9c, requires exactly their two missing-feature failures, then executes
all actual EditorCore/Highlighting/Themes controls on the candidate, in Debug and
Release. Both source/pin inventories, actual helper/product digests and statuses
are retained. Empty/EOF/wrapped geometry and a scrolled source above 10 MiB are
additional candidate controls. The real app status-bar test mounts a hosting view,
changes through every bundled theme and samples actual background pixels; it is
not a substitute for owner visual/VoiceOver acceptance. All native execution stays
hosted. Preserve any first geometry/capture failures and classify them before merge.


## First hosted geometry findings

The exact common fixture fails precisely its two absent-feature assertions on
baseline 6667bc9c and both pass on candidate 4a3bc7cf. The complete Debug subset
executes 1,082 tests/142 suites and finds three issues: empty source has no layout
fragment; a terminal newline places a zero-length final visual row inside the
preceding paragraph fragment, so selecting its logical final line paints nothing;
and the existing gutter glyph-orientation score is contaminated or regressed by
the new active-line cue. Retain all first results and do not weaken thresholds.
The scrolled 10,530,000-byte draw visits 38 fragments in 1.1925 ms (Debug diagnostic,
not whole-editor Release proof).

Use TextKit 2's explicit ensuresExtraLineFragment only in the existing bounded
viewport enumeration; the zero-length document may start directly at its known
start. Recognize a terminal empty row only when its native zero-length range
matches the incremental line index's exact final empty-line offset. Share this
small native geometry rule between background and gutter. Exclude that final row
from the preceding logical line's background and emit its own gutter number.
Never force layout to a distant caret or traverse all wrapped rows.

Keep the gutter orientation threshold and flipped-matrix mutation check. Record
its actual primary selection, and isolate the numeral's columns from the new
separate shape when testing glyph orientation; the shape has its own real bitmap
positive/negative control. This is fixture isolation of two independent visual
contracts, not permission to accept an inverted numeral or drop the marker.


The first Release comparison never executes: its baseline build reaches the
900-second compile limit while building every unrelated package test target.
Keep that deadline and the complete independent CI. The focused comparison will
compile the actual EditorCore/Highlighting/Themes products through a small test
package with byte-identical copies of all three original test directories and
the same declared product dependencies; baseline copies only the common fixture.
No test uses Bundle.module or source-relative fixture paths in these directories.
Record/verify copied test bytes, manifest, all original source hashes and all 24
locked owners/revisions before and after execution. Do not adapt production
sources, replace a native type or omit any of the 1,082 selected candidate tests.
The native glyph-orientation mutant and restored positive control also use those
same actual products, with exact source restoration and separate execution hashes.


## Qualified Debug behavior and stricter optimized regression

At 77ada868 all 1,082 actual editor/highlighter/theme tests pass in Debug. Both
common baseline controls still fail exactly as expected; native empty/EOF rows
now paint. The actual orientation mutant scores 0.1886 and fails the unchanged
>0.6 assertion; restored production passes. Release executes the entire same
corpus and all current-line controls pass, including the 10 MiB draw's 38 visits
in 0.789167 ms. Its sole failure is an inherited Release-only widened-edit test:
withKnownIssue now reports that no issue occurred because edited/fresh parity
actually matches. Remove that stale expected-failure wrapper and require actual
nonempty, equal rendered output as a strict Release regression. Do not mark the
separately recorded Debug abort fixed or enable its unsafe experiment; #19 still
owns controlled native interleaving/root-cause qualification. A future Release
parity failure must fail normally, not be masked as intermittent.

There is no functional ordering dependency on PR98. The first independently
qualified branch may integrate first; the later branch must synchronize with it
and qualify the exact combined tree before merge. Owner acceptance and every
wider E22/E23 gate remain explicit.


## Combined-source qualification

PR98 is merged as `ee45cc25d43c9cf6b067ad4d2674312a96f7cb1e` with all
package/application and Debug/Release heading/native controls passing. This
branch now incorporates that exact main without conflicts; both activation
paths require fresh complete CI and native Debug/Release controls on the
combined source before integration. Original baseline 6667bc9c remains the
immutable missing-feature counterexample, not the merge base. The prior d9
current-line native runs pass all 1,082 tests/142 suites in both configurations,
including strict nonempty Release edit/fresh-highlight parity and the actual
glyph-orientation mutation/restoration control. These earlier results do not
replace final combined-source qualification.

## First combined application pixel findings

Combined source 7c5891b7 completes package tests and all app/CLI builds; its full
app run executes 671 functions/141 suites and fails eight channel comparisons
in the new status-bar test only. Tomorrow Dark captures 0.232248 per channel
against nominal 0.176; Slate and Midnight also differ, while white/black and
warm light themes remain within the original tolerance. Raw logs and the first
failure remain retained. These are not a green status-theme acceptance result.

The initial fixture asks AppKit for an implicit cached-display bitmap and
compares deviceRGB components to an sRGB palette. Before changing production
colors, render into an explicitly sRGB-tagged bitmap and verify readback with
an independent Core Graphics solid-color reference in the same bitmap. Keep
the original 0.03 status-channel tolerance and all eight themes. If calibrated
capture still differs, diagnose/remediate the production bridge rather than
relax the oracle. Select this actual app control in both native configurations,
alongside the unchanged 28 math/heading controls. Complete exact-source CI and
combined Debug/Release qualification remain required after any correction.

The b0f78750 native Debug run executes all 29 functions/9 suites. Its AppKit
solid-color reference returns exactly the same shifted components as the
status bar, including nominal 0.176 becoming 0.232248. The calibration itself
fails, so the result does not establish a production status-color defect.
Retain all 19 failed assertions. Next inspect raw pixel samples in the declared
sRGB bitmap rather than constructing/converting NSColor through colorAt().
Calibrate that sampler with a separate fresh Core Graphics bitmap filled from
explicit sRGB components (no NSColor bridge), require opaque RGBA/8-bit storage,
and preserve the original status 0.03 and reference 0.01 channel bounds. Keep
production colors unchanged unless that independent calibrated oracle identifies
a mismatch. This is a readback investigation, not a tolerance exception.

# E23 Mac integration implementation

## Owner summary

Give MostlyText one coherent theme across its editor, native Markdown preview
and export, then add safe custom themes and a bounded Markdown Quick Look
extension. Source stays authoritative and first-party rendering stays offline.
This architecture consumes the detailed contracts in
[the E23 handoff](downstream/issue-113-handoff.md); it does not mark E22 or E23
accepted or replace the final CORTANA evidence gate.

## Current baseline and first executable unit

Current master is 15c0fae22f7618e94c82681227057c66011be2a9; the accepted
integration baseline is 7b8b4055796d7452fc6dd1b27ced71470c92623c. Theme and
presentation interfaces are the same on these baselines. The current-line
PR #520 remains separate and its native/performance failures are not waived.

Themes currently owns Theme, EditorChrome, capture fallback, immutable bundled
resources and independent appearance slots. ThemeController already checks
slot appearance; do not reimplement that old handoff finding. PreviewTheme
hard-codes links and independently mixes colors. ExportThemeStylesheet has a
second set of mixes. NeonSyntaxHighlighter applies editor chrome directly.
Only two bundled themes exist, and there is no Quick Look target.

The first bounded unit changes only these already-stable value interfaces,
presentation adapters and bundled theme data. It does not depend on E22's
outstanding native acceptance and does not redesign any editor behavior.
The remaining custom-theme, presentation and Quick Look units retain their
handoff prerequisites and named feasibility probes before implementation.

## Semantic palette contract

Themes owns immutable ResolvedPresentationPalette, derived from a value Theme.
It resolves editor background/foreground/caret, selected background/foreground,
current line, gutter/status, invisibles/secondary carets, heading/link, muted/rule,
code foreground/background and quote foreground/background/border. Existing
capture fallback remains authoritative for heading/link. Missing roles get one
deterministic fallback here; adapters do not invent another palette.

PreviewTheme and ExportThemeStylesheet consume the same values; export keeps
its existing print-safe structural overrides. NeonSyntaxHighlighter uses the
same editor roles without reconstructing the text system or touching parser,
source, selection, undo or document generation. PR #520's current-line drawing
is integrated only after its owning source and native gates pass.

Code background is a faint eight-percent raw-markup tint over the document
background. Body foreground remains code foreground. Quote text remains body
foreground. Link colors follow the theme's markup.link capture, with body
foreground fallback; changing appearance alone cannot replace an authored
custom link color. Selection foreground uses the body foreground, preserving
existing editor behavior. Decorative separator/quote borders share one blend.

## Bundled themes and compatibility

Keep tomorrow-light and tomorrow-dark identifiers and default slots. Rename
only the light theme's display name to GitHub Light because its verified
provenance is GitHub's syntax palette, not Tomorrow; retain its existing file
name and stable ID for compatibility. Do not replace current light token
colors with guessed Tomorrow values.

Add six original first-party palettes: Paper, Daybreak, High Contrast Light,
Slate, Midnight and High Contrast Dark. With the retained two defaults this
provides four light and four dark choices. Their JSON is declarative data,
uses the canonical capture roots and has no fonts, executable CSS or URLs.
Record first-party provenance and exact resource hashes in compliance.

Bundled body/link/code presentation roles must reach 4.5:1 on their resolved
backgrounds; high-contrast body roles must reach 7:1. Add regression checks for
unique IDs, appearance counts, opaque backgrounds, finite channels and role
contrast. This is automated readability evidence, not a VoiceOver/visual pass.

## Verification and failure handling

Pure Theme/PreviewTheme/Export stylesheet regressions cover custom links,
fallback roles, appearance differences, shared code colors and print rules.
The existing controller/fallback/capture tests remain intact. Correct the old
exactly-two-themes assertion to the new required catalog size, and assert that
old IDs still resolve. Unknown custom imports remain outside this unit.

Run locked focused package tests without native windows, strict lint/format,
source compliance and Release compilation. Record source and fixture hashes.
Live switching, selection/viewport retention, eight-theme visual review,
settings controls, custom-theme lifecycle, Quick Look and exact signed-artifact
verification remain required before E23 closes. No public release follows
from this foundation unit.

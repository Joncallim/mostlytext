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

## Custom-theme file admission unit

The next unit adds ThemeFile v1 as a validated value codec, without file-system
writes or a new UI. Its envelope is schemaVersion, UUID stableID, displayName,
appearance, chrome and tokenStyles. Constructing a custom copy generates one
UUID; encoding/restart/reimport retains it. Its Theme ID is the lowercase UUID,
so imported data cannot claim a bundled theme ID or become a filesystem path.

Limit input and canonical output to 64 KiB, object nesting to eight, token
styles to 512, capture names to 96 ASCII bytes and display names to 80 Unicode
scalars. Require opaque base backgrounds and finite 0...1 color channels.
Reject unknown/duplicate/escaped-duplicate keys, arrays, wrong field types,
invalid UTF-8, future schemas and invalid IDs. Preserve caller bytes on every
failure; the codec performs no I/O. Custom poor contrast is not prohibited;
Appearance UI will warn without silently changing intentional colors.

Only the codec exposes untrusted-data admission; its private Codable envelope
cannot bypass validation through a public synthesized Decodable initializer.
The catalog writer, explicit Replace/Copy/no-op flow, imported-file grants,
watcher, migration integration and native evidence remain subsequent units.

## Stateless byte-decoding unit

Quick Look needs the editor's strict encoding policy without creating document,
session, recovery or filesystem-observer objects. FileCore already has that
policy in FileStore's value decoder. Expose FileByteDecoder.decode with an
explicit caller-owned maximumBytes and FileDecodingPolicy, returning an
immutable public FileDecodedPayload (text, encoding and BOM). Check the byte
ceiling before copying/decoding. Reject negative limits explicitly. Normalize
Data slice indices into an owned zero-based snapshot before the existing
validator runs; do not add a second encoding detector or lossy conversion.

This API performs no I/O and has no MainActor state, work queues or cancellation
ownership. Its work is synchronous and bounded by the caller's admitted byte
budget; consumers must run expensive admitted work off the reply/UI executor.
Automatic decoding remains strict BOM/UTF-8. Legacy encodings require explicit
policy and lossless round-trip. Preserve EOLs, BOM metadata and diagnostic byte
offsets. Test empty/Unicode/mixed EOL/BOM/UTF-16/legacy/invalid byte cases,
nonzero Data indices and exact/over-limit admission. Existing FileCore encoding
regressions must remain green. This does not implement a filesystem reader,
large-file prefix preview or prove Quick Look execution placement/timing.

## Catalog import-decision unit

Themes owns immutable ThemeCatalogSnapshot values (revision plus at most 256
validated custom ThemeFile values, unique UUIDs) and a pure ThemeImportPlan.
Preparing a plan validates input, then reports a same-content existing entry,
a recognized-ID conflict requiring a choice, or a new import. Compare content
without UUID so reimporting an unchanged external file is a no-op even when its
first admission assigned a new managed UUID. Recognized IDs take precedence over
other content matches. Import Copy always generates a fresh managed UUID;
unrecognized external IDs never become implicit replacement authority.

Resolving a plan requires the unchanged catalog revision and an explicit choice.
A recognized conflict can produce Replace only with the original entry's exact
canonical digest; Replace retains that managed UUID. New imports and copies get
a generated UUID checked against the catalog. Return immutable proposed changes,
not writes. The filesystem writer must independently verify current on-disk
bytes immediately before publication; this pure check is not a filesystem
transaction. Invalid choices, duplicate catalog IDs, a full catalog, stale
revisions/digests and generated-ID collisions fail without mutation.

Keep this unit in Themes, using CryptoKit only for deterministic SHA-256 of
canonical bytes; no new package dependency or file access. Test new/copy/no-op/
replace, restart-equivalent snapshots, foreign ID collisions, stale dialogs,
count bounds and invalid choices. The actor writer, watcher, app-wide catalog
publication and Appearance UI remain subsequent units, not fabricated passes.

## Bundled-theme Appearance controls

Add one native Appearance settings tab using the existing ThemeController and
appearance-mode owner. Show separate light/dark pickers, the current semantic
sample and a reset-to-bundled-defaults action; do not create another appearance
preference or change document content. Use ordinary Form/Picker/Button controls,
actual capture colors for representative code, and prose/heading/link/quote/
selection samples. Theme names remain proper names; action/sample labels enter
the app String Catalog with translations marked for review. Keep custom import,
export and delete controls absent until their persistent implementation exists.

Expand the shared settings content size to fit six native tabs and the sample.
Existing rendered-state/pseudo-localization fixtures consume that same declared
size rather than retaining a stale fixed capture rectangle. Compile and lint the
view, retain native focus, resizing and VoiceOver/pseudo-localization review as
real CORTANA gates, and do not claim those outcomes from compilation alone.

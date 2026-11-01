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

## Shipping-SDK declaration reconciliation

The current macOS 26.5 SDK requires explicit QLPreviewingController conformance
on the QLPreviewProvider subclass. The older handoff's contrary instruction is
corrected with a failing inherited-method control and passing explicit-protocol
control in evidence/quicklook-api-2026-11-01. The async providePreview method,
HTML reply, String.Encoding property and PNG attachment compile into a library
without packaging/registration. Runtime QL-REPLY remains held; this declaration
correction does not answer callback placement, cancellation, grants or timing.

## Managed custom-theme persistence unit

ThemeCatalogStore is one actor in Themes; it owns a pinned descriptor for an
existing private, owned directory supplied by bootstrap. Internal filenames are
lowercase UUID.json, independent of the still-frozen public theme extension.
Do not read the real Application Support directory in tests. Open the root
without following symlink components, require owner-only permissions and refuse
ownership-ignoring volumes. Bound a scan to 1,024 entries and 256 managed UUID
files, and each regular single-link file to 64 KiB. Read descriptor-backed owned
bytes, compare object metadata before/after and validate UUID/filename identity.

Prepare imports from caller-admitted immutable bytes. The app will use its
existing LocalResourceAccess single-file reader under the explicit panel grant;
the store never retains an external URL. Reuse ThemeImportPlan for choices,
with store identity and current raw-file baselines bound to prepared operations.
Serialize reload, import and delete inside the actor. No await occurs between
baseline verification and publication. Cancellation can stop admission before
mutation; it cannot turn an already-published success into a reported rollback.

A staged managed file is exclusive-created through the root descriptor, mode
0600, fully written/flushed, then atomically published. New IDs use exclusive
rename. Replace uses atomic exchange on supporting filesystems, verifies the
displaced object and raw digest, and rolls back if a competing edit won. Never
fall back to an unchecked replacing rename. Preserve displaced bytes under a
reported recovery filename if another writer makes rollback unsafe. Delete
first moves a target to an exclusive private staging name, verifies it, then
removes only the unchanged object; preserve/restore unexpected bytes instead.
Root-name changes, symlinks, hardlinks and stale baselines refuse publication.
Directory-flush failure after successful publication is a durability warning,
not a false claim that the old state remains on disk.

Reload returns immutable revisioned themes and bounded diagnostics. During an
incomplete external write or transient deletion, retain the last known good
value for a 750 ms confirmation window; a stable repeated invalid/missing
observation then excludes it without deleting any bytes. A valid observation
clears the diagnostic. Return a recheck request while confirmation is pending.
One later app-level watcher will debounce directory events and schedule that
recheck; per-window watchers are forbidden. Count admission includes retained
entries so transient failures cannot exceed 256 app-owned theme values.

Test exclusive creation, restart/export identity, real replace/copy/no-op,
interrupted publication, exact stale-before/exchange/rollback interleavings,
symlink/hardlink/directory/oversized rejection, root replacement, bounded scans,
external corruption/deletion/recovery and actor serialization. Internal test
hooks model the exact syscall boundaries; no sleep-based race test or real
user preference store is needed. The app-wide watcher, preference coordination,
Appearance management controls and native journeys remain subsequent work.

## Live catalog selection integration

ThemeController remains the sole MainActor appearance/selection owner. Preserve
saved preferred light/dark IDs separately from temporary displayed fallbacks,
so a catalog loaded asynchronously can restore an existing custom selection
without rewriting preferences. A user choice made while loading wins; saving
one slot must preserve the other slot's still-unloaded preferred ID.

Apply only strictly newer immutable catalog revisions. Keep bundled fallbacks
available even for an empty custom catalog. When a previously available,
correct-appearance selected custom theme is removed from a confirmed snapshot,
fallback and persist that slot once. An unknown/future choice that was never
available is displayed with a safe fallback but retained in preferences. A
custom theme changing appearance invalidates only its old slot, not the other
choice. Accept menu selection only from the current validated catalog, using
its current value rather than a stale captured Theme. Reset both choices in
one controller operation without changing the appearance mode.

Test delayed catalog load, user choices during load, preservation of the other
unknown slot, stale reload suppression, selected deletion/appearance change,
empty fallback, reset and stale/foreign menu values. These are selection-value
regressions; source/undo/viewport retention and real switching latency still
require CORTANA native verification.

### Reproduced theme-preference compatibility correction

Synthetic-suite tests found that a partially stored theme pair was discarded
by loadSelection, and a later choice replaced its valid saved slot. Numeric
and Boolean objects were coerced into IDs by string(forKey:); ordinary saves
also replaced unreadable raw values and unknown future appearance modes.
The failing-before log records 16 issues in six preference tests; no real
user preference domain was opened.

Apply the existing AppSettings no-clobber rule to the theme-owned keys: admit
only absent or bounded clean String IDs, preserve a present valid slot when
the other is absent, and refuse an ordinary pair save when either existing
value is unreadable. An unknown/malformed mode blocks that mode's writes while
leaving a readable selection pair writable. Recheck at the write boundary.
Report the persistence problem through the existing settings warning so an
ephemeral UI choice is not mistaken for a successful save. This does not create
a legacy importer or claim UserDefaults is a multi-key transaction; E17's
journal/before-desired checks remain required for migration.

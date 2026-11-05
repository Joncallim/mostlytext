# Prove original-source equations can use the existing native attachments

## Owner outcome and scope

Equations must retain their original TeX and source identity when Markdown
contains escapes, formatting and reference links. Before replacing the current
math paths, prove the actual pinned Textual parser and SwiftUIMath attachment
can carry those values without losing surrounding links or leaking transport
markers. This slice is a native parser/attachment feasibility probe, not a new
production scanner or an activation of the full math architecture.

Current merged main is68801d650dbd174f1cbc810617b43e7c22afdffd. The branch
includes prepared PR80/81 source through03cba92ccc55107569bf8583b9e244770d9f5f23;
those integrations must pass first. Existing Textual owner revision is
d3ddabb1da37681083cdc3da706f96cf2fb6a3c6 and SwiftUIMath identity/pin stay exact.
Consume issue-116-handoff.md and RELEASE_HARDENING.md; original-source admission,
shared grammar, diagnostics, accessibility/navigation and final parity remain
mandatory later. Do not treat this probe as any whole issue's closure proof.

## Focused architecture reconciliation

The handoff originally requires vendoring exact dependency sources. The app now
already uses an immutable owner Textual fork with preserved upstream history.
Use a narrow child of that exact revision instead of another source copy. Add
only a typed factory for its existing MathAttachment. Keep the concrete type,
style/layout implementation and old post-parser math behavior unchanged. An
optional caller-owned UUID distinguishes source occurrences; it is independent
of render-body equality and never derived from a transport marker. Default nil
preserves existing callers. No other package identity or version changes.

The first executable source-position spike uses Foundation only, no AppKit,
SwiftUI, WebKit or app. Actual source confirms collapsed-reference loss:
[MARK][] no longer resolves the unchanged [$x$] definition; [MARK][$x$] does.
It also confirms that Markdown can synthesize a marker across attributed runs
or from an HTML entity even when its raw spelling was absent in source. Counts
alone therefore do not establish marker provenance.

## Probe ownership and fixed interfaces

Keep the experimental transport in PreviewTests until the actual adapter proof
passes. It receives pre-admitted immutable fixture spans (original UTF-16 range,
unchanged TeX, inline/display style, occurrence UUID) and parser-derived reference
metadata. It does not scan dollars or admit authored URLs as attachments. Source
admission and the production MathSyntax dependency remain a separate unit.

For collapsed/shortcut reference labels touched by an equation, retain the
original raw reference key explicitly. Full reference keys and original
reference definitions stay unchanged. Link targets/title bytes are never
reconstructed from markers. This is the handoff's required reference-identity
correction; no authored/disk/session/undo source changes.

Build a transient string with nonoverlapping edits in one forward pass, tracking
each generated marker's rewritten UTF-16 range and original full span. Include
prepended definitions in namespace-absence checking. Bound input/span counts,
validate scalar boundaries and overlap, and reject conflicting metadata. Generate
one absent alphanumeric UUID namespace; marker identity is transport-only.

Parse through actual AttributedStringMarkdownParser with .math disabled and
Foundation source-position attributes enabled. Find registered markers across
attributed runs. Every occurrence must be unique, retain source-position ranges
covering its exact generated-input location, and lie outside preformatted runs.
Reject unknown/missing/duplicate/misplaced markers. Replace them with the actual
typed AnyAttachment.math factory while retaining surrounding attributes. On any
adapter failure return readable original source, never opaque text or guessed
navigation. Original identity and expression bytes survive unchanged.

## Execution and required outcomes

Locally execute only inspected Foundation-only source-position/transport units;
compile actual PreviewTests without executing native code. Run actual Textual,
SwiftUIMath metrics and paragraph construction in hosted macOS26 package tests.
Local native EXECUTION_HOLD stays in force; no owner app/helper/window runs.

The probe must cover escaped dollar plus real math, Markdown punctuation,
multiline percent comments, emphasis/link labels, literal code, repeated equal
expressions with different IDs, full/collapsed/shortcut references (including
shared definitions in another block), Unicode and CRLF, and missing/duplicate/
misplaced markers. Compare targets against the original actual parser, preserve
original reference-definition/title bytes, assert exact original source ranges,
unchanged equation bodies and actual typed attachments. Verify paragraph text
order plus actual attachment metrics and native text construction/layout. Keep
all first failures. No timed sleeps, test/deadline weakening or alternative math
renderer is permitted. Geometry evidence is distinct from final visual/VoiceOver
acceptance, which remains required later.

If actual source-position provenance, reference semantics, typed attachment
layout or one-engine resolution fails, stop this probe's dependent integration
for a focused design revision. Pure grammar/value work can continue. Publish a
pinned child and merge only after original licences/inventory, compile, all
app/package/CLI checks and exact-head review pass. Update issue9/#17 with its
precise partial scope, immediately reassessing all open issue contracts.

# Activate one source-owned math path in Preview and Export

## Owner summary

Equations will be recognized and checked once against the author's original
Markdown. Preview and Export will use the same bounded grammar, exact equation
body and failure categories. Invalid or valid-but-invisible equations remain
readable source with an explanation; a source action selects the right occurrence
only while its document and source snapshot are current. Generated content and
pending/oversized text do not receive another dollar parser.

Main e8201ad8925aaf0cac2f15fafbda285c773a1d05 contains PR90/91 with the qualified
source transport. The integration branch adds the typed, allocation-bounded raster
API (37 hosted native controls already pass) and actual parser-consumed reference
metadata. Current ba7d43d2 guards native link/image replay against the original
whole-document source facts. Its hosted 45-function qualification is pending;
production cannot adopt this path until those exact controls and complete CI pass.
This document defines the next implementation slice before its broad edits.
The parent shared-math production/activation and parser-reference-replay contracts
remain binding. This changes no release, signing or protected-account hold.

## Shared recognition and rendering policy

MathRendering owns the actual engine body and typed evaluation. A single processing
policy supplies both destinations: at most 512 admitted occurrences, at most 8192
UTF-16 units per body, parser depth 64 and 100000 parser steps per body. These are
provisional safety ceilings, not final responsiveness calibration. Cancellation
abandons a complete result. No legacy MathSpanScanner, newline flattening or
Textual .math extension participates in either production destination.

Both destinations measure accepted bodies with the same engine/type style before
choosing a visible attachment/image. Zero ink/height is a distinct valid no-visible-
output fallback, never malformed syntax. Native attachment drawing remains Textual's
existing typed body factory and environment font refresh; raster output remains
the existing typed ImageRenderer API. The old public span/String factories stay
compatible for existing callers and tests.

Math owns first-party localized diagnostic prose for the existing structured kinds
plus noVisibleOutput. Original equation IDs/ranges and diagnostic source offsets
come from MathEvaluation; engine free-text messages never become UI prose.
French/Japanese/Polish new entries are needs_review, without claiming translation
or final layout/VoiceOver acceptance. A generic contribution diagnostic may carry
an optional original source range, opaque occurrence ID and stable category code;
Export preserves this metadata rather than inventing a second math classification.

## Export producer and bounded readable fallback

An additive SharedMathContribution in MathRendering implements the existing
Contributing protocol and replaces only the registered production MathContribution.
It uses the same MathAnalysis/MathEvaluation/policy as Preview, then typed body
rendering. Its direct Contributions dependency is explicit; Math stays free of UI.
Each successful equation yields the existing self-contained, escaped PNG image
fragment at its original range. Original label repairs remain owned by the current
DerivedContentComposer and ordinary original-source reference context.

Malformed, unsupported, renderer-failed, resource-limited and no-visible-output
occurrences contribute an HTML-escaped authored literal, using fixed first-party
markup. Their structured warning explains why source is shown; they are safe
successful fallback content, not failed arbitrary HTML. Existing admission of
contributions with .error diagnostics is unchanged. Source bytes are never edited.

Before constructing base64 or accumulating results, admit aggregate PNG bytes
(16 MiB) and generated HTML bytes (24 MiB), also retaining the existing per-image
8 MiB/geometry limits. Count exact escaped UTF-8 bytes and base64 expansion before
allocating output. Do not allocate an unbounded authored substring to learn it is
too large: operate over validated original UTF-16 slices/scalars and admit first.
Final ExportService source/derived/resource/HTML publication gates remain active.

If a safe literal fallback cannot itself fit, or source authority cannot be
established, return a fatal structured diagnostic and no partial math snapshot.
Add an opt-in preventsPublication flag to ContributionDiagnostic/ExportDiagnostic,
default false for all existing producers. ExportContributionAdapter forwards it;
the ordinary coordinator rejects fatal standalone diagnostics before publication,
and ExportService rejects fatal attached diagnostics. A specific localized export
error reports them. This adds a hard failure path; it does not relax existing
failed-content, URL, resource, cancellation, raw-HTML or publication admission.
Source-anchor metadata alone never authorizes navigation.

At the occurrence cap, preserve a literal remainder and report resourceLimit. Both
destinations use the same original top-level block boundary: downgrade the block
containing that remainder and subsequent authored source to readable text, instead
of applying another math pass or partially rendering an uncertain tail. Whole
source/HTML admission still applies to the fallback; an oversized export refuses
publication. Cap behavior is tested with small injected limits and exact source.

## Trusted Preview blocks and native transport

Source-derived PreviewBlock carries a source SHA and original UTF-16 range. Only
the original document slicer creates that anchor. A bounded subrange operation
allows the contribution composer to retain it for unchanged authored fragments;
inline-composed/generated fragments receive nil. Stable block IDs remain as built.
The preview display cache stops applying the legacy newline preprocessor.

An app-prepared immutable Preview math content value contains per-block guarded
PreviewMathInput plus caller-owned typed attachments. Preview itself gains no
MathRendering dependency. Build the reference-use index once per source snapshot,
select only actual used definitions, derive block-local original link/image
references, and apply shared original-key repairs alongside equation markers.
Every fully expanded input, including definitions/markers/repairs, stays at 64 KiB.
Unknown/ambiguous/budget-exceeding source input visibly degrades to its authored
block. Native URL replay passes the actual source-authority check before any
attachment restoration. A validated zero-output/rejected equation restores its
literal source in the original permitted Markdown attributes, without an attachment.

All other blocks use a parser with syntaxExtensions [], including generated,
pending, no-equation and oversized tails. Generated contributions retain their
existing admitted Markdown behavior and URL/resource policies but cannot mint
math occurrence/source-action authority. Parser content identity changes when
analysis arrives even if the text did not change; do not retain stale Textual state.

## Live state, cancellation and own source actions

A per-document observable MathPreviewSession owns one MathEvaluationWorker and one
current immutable result. The existing worker retains its physical slot until
noncooperative work actually exits, with only the newest pending request.
An exact SourceAnalysisText change immediately invalidates visible math state.
The math task key includes tab/document identity, recovery lifetime, mutation
generation, parse-session identity and parsed revision. A nontext save/generation
change refreshes/rebinds exact unchanged source rather than leaving math pending
forever; the separate existing TOC task/cache key remains unchanged.

After awaiting, publication re-reads the live WindowCoordinator/controller/model,
active tab, current document recoveryEpoch/mutationGeneration, existing editor
source, and existing parse-session identity/source/revision. The frozen request
must match exact UTF-8 bytes as well as these lifetimes. A captured SwiftUI value
or equal current source hash alone is insufficient. Reset/removal cancels the
caller; no late result revives a closed/replaced document. Shutdown permanently
rejects new requests and retains physical running ownership until completion.

Per-occurrence accessible Textual descriptors use the original equation body as
readable context, localized equation/source action names and their own opaque ID.
Preview diagnostics have localized summaries and own source buttons. Every action
repeats the same live checks without an await, resolves only an ID/range from the
current immutable snapshot, resets EditorSelectionSet(single: ownRange), then
reveals the selection in its actual editor. Invalidate pending folder-search
reveals through folderSearchNavigationDidChange. A closed, changed, other-window,
Save As or reopened-same-path document makes the action a no-op. No parser marker
text, guessed formula search or captured old editor string grants authority.

## Implementation and evidence sequence

1. Qualify original reference replay/URL guard on all 45 actual hosted controls;
   retain first failures, correct source/title/image/Unicode checks without weaker
   assertions, and run full package/app/locked Debug+Release builds.
2. Add shared policy, typed bounded Export producer and diagnostics/fatal carrier.
   Test actual parser outcomes, raw comments/braces/delimiters, exact source ranges,
   valid empty/spacing, injected renderer failures and pre-base64 aggregate limits.
   Prove arbitrary .error fragments remain rejected and fatal paths write nothing.
3. Add trusted block anchors, app-prepared native payload, physical-session/live
   stamp guard and source action. Test exact Unicode/CRLF/ABA/lifetime/cancellation/
   nontext-generation transitions, source fragment authority and no-secondary-parser
   behavior. Compile real app locally without launching it; run native mounted
   component/UI-dependent tests only in hosted macOS26 CI.
4. Activate Preview and Export together. Run complete exact-head qualification and
   review source ownership, failure/authority, state/lifecycle, budgets, localization
   and compatibility as separate passes. Merge only the actually qualified tree.
   Update owning issue checklists only for complete proved rows, then audit all
   open issues again. Delete merged app branches only after verified recovery.

Final owner-account UI/VoiceOver, native visual/PDF parity, whole-app Release
performance calibration and exact signed candidate evidence remain explicit gates;
package timing, fixture accessibility and integration merges do not establish them.

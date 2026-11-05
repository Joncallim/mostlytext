# Shared math production integration

## Owner summary

Preview and Export must consume the same source-owned equation admission and
actual parser result. They must preserve authored text, diagnose malformed math
at its own source position, and stop reinterpreting dollars or flattening comments.
Rendered equations need meaningful accessible representation and their own safe
source navigation. This work completes software convergence toward #9; native
visual/VoiceOver, final Release and exact-artifact acceptance remain separate.

## Baseline and prerequisite state

Current main 7e8e5a26f72cc21de34e6cabc3522cf44a493f5b contains merged PR87; its full
CI passes 3,512 package tests, 619 app tests and all four locked builds. Prepared
PR88 head 2e61c096008495be249318a742ef3d8559600083 provides stable opaque body
interfaces through engine2a89c2b41482988711909572d116374e47a52164/Textualb940433c7a55b82a8bbbe6fb0837df7162307dbb.
Its native metrics/cache and accessibility probe still need complete hosted
qualification. This branch starts from that exact source; do not merge dependent
production activation before its prerequisite passes and integrates.

The production path still uses independent MathSpanScanner/legacy newline
preprocessing and Textual's math extension. Source-bound MathAnalysis and the
native typed factory are qualified prerequisites, not current shared consumers.
The scoped implementation below is ready; broader activation remains a named
architecture decision until actual code paths and the native probe resolve it.

## Ready slice: observe exact authored source changes

The live DocumentEditorSplitView.onChange(of:text) compares Swift Strings, whose
canonical equality ignores distinct authored Unicode spellings. The existing
editor/model preserves these edits, but Markdown/JSON analysis may not be
requested. FileDocument.edited assigns exact text and advances mutationGeneration;
EditorView already uses exact comparison, and MarkdownParseSession.textDidChange
always schedules when called. This is an observation gap, not evidence of file
persistence loss.

Use an immutable SourceAnalysisText value holding the existing COW String. Its
Equatable comparison uses exact UTF-8 bytes, with no normalization, hashing or
fingerprint collision. SwiftUI observes that value and passes its captured text
to the same Markdown/JSON callbacks and unchanged format gates. No new parse,
worker, file write, UI string or native execution boundary is introduced.
Nontext saves/settings remain outside this trigger. Source equality is linear
in the existing source size; no byte array or digest is allocated on view
construction. Existing source snapshots already retain the previous COW value.

Allowed files: the value helper, DocumentEditorSplitView's source observer and
its explanatory references, app value tests and exact Foundation evidence.
Tests must distinguish canonical-equivalent pairs (including same UTF-16 and
UTF-8 lengths), identical bytes, line endings, source-only whitespace/NUL and
immutable captured values. Record the original String-comparison counterexample.
Compile the actual app through hosted CI; local execution copies only the exact
Foundation helper/tests into an isolated package, never SwiftUI/AppKit/products.
This correct observation does not establish mounted UI publication or final math
parity by itself. Preserve all existing parser/lifecycle assertions and timing.

## Remaining decisions before broad activation

- Preserve the Preview module's renderer boundary: consider app-prepared native
  attachment payload values with source-bound MathEquation metadata, since Preview
  already owns Textual. Keep actual engine validation in MathRendering; do not add
  a Math-to-UI dependency implicitly.
- SourceMap-derived Preview blocks need trusted original UTF-16 origin/binding.
  Generated TOC source cannot mint equation identities by matching text alone.
- Actual scalar-safe marker restoration must verify original-source provenance,
  exact one-to-one registry matches, non-code intent and bounded expanded input.
  Include reference-key repair for collapsed/shortcut links in both destinations.
- The immutable result needs exact document lifetime, generation, source hash and
  per-equation body/diagnostic identity. Map parser offsets back through the
  existing expression-source segments. User diagnostics require localized first-
  party categories, with renderer failures separate from malformed input.
- Use one physically running analysis and one newest pending request; cancelling
  noncooperative work cannot free its slot early. App publication/source actions
  recheck current lifetime/generation/exact source after any actor suspension.
- Disable secondary dollar tokenization for every block, including pending,
  literal cap tails, generated content and blocks without admitted equations.
  Analysis arrival must invalidate native parse state even when text is unchanged.
- Valid empty/comment-only equations and zero glyph bounds need a common readable
  fallback policy; zero geometry alone must not be labeled malformed math.
- Use the actual PR88 accessibility tree observation before choosing MathView
  labels versus per-occurrence geometry/representation. Final VoiceOver remains
  held. Check the TextFragment font-environment refresh hypothesis with a focused
  native control before altering that renderer state.

No local native/product/CLI/signing execution, hosted source renderer, document
source rewrite, second Export renderer, unrelated theme changes or release/source
publication is authorized by this slice. Issue updates always retain their actual
scope and are followed immediately by a fresh repository issue audit.

## Prepared evaluation and physical worker contract

The positive-controlled native PR88 probe at 9e23f928 observes the standalone
equation label but no inline label: Canvas drawing does not expose its symbol
view's semantics. Production must add an accessible per-occurrence representation
at actual attachment geometry with a source action; a label on MathView alone is
rejected. Native final VoiceOver remains held.

Before adapters activate, Math owns renderer-neutral diagnostic categories,
equation ID and original scalar-safe source offset. MathRendering owns an immutable
MathEvaluation with the exact MathAnalysis and one outcome per admitted equation:
accepted opaque engine body, invalid syntax, internal parser failure or resource
limit. Use the actual engine parser codes; never classify zero glyph geometry as
malformed and never display the engine's unlocalized free-text messages. Error
positions map through MathEquation's existing original-source segments; an invalid
engine boundary falls back to that equation's own body start, never another span.
Successful empty/comment-only bodies remain accepted. Cancellation aborts the
complete result instead of publishing a partial snapshot.

MathRendering also owns a per-document MathEvaluationWorker actor, with explicit
immutable request source/document/identity/generation and caller-selected positive
span/body limits. Its only production computation is structural MathAnalysis then
actual body evaluation on a detached task. Add direct MarkdownEngine/MathSyntax
dependencies for these used types; no new remote or Preview-to-renderer dependency.
A worker keeps exactly one physical task and at most one newest pending request.
Superseded callers return promptly, but cancellation never releases a physical
slot before the underlying task actually returns. Caller cancellation removes
only its own request. Shutdown rejects new requests and resolves waiters while
retaining physical ownership until completion. Results publish only to their own
request continuation. App consumers still must recheck live lifetime/generation/
exact source after awaiting; worker completion alone cannot authorize navigation.

Tests use actual parser/source models, comments/empty valid bodies, invalid
commands/braces, parser bounds and source-coordinate projection. Worker tests
use an explicitly released noncooperative fake computation, proving a newer
request waits physically, pending replacement/caller cancellation/shutdown,
independent document instances and error recovery. Execute only exact inspected
Foundation/C/CryptoKit files in an owned fixture; the engine's unused outer
SwiftUI View is replaced by the already documented empty Math namespace. Compile
actual targets locally, execute native component tests only on hosted CI. This
is a dependency unit; Preview/Export activation and whole criteria remain open.

## Inline accessibility representation decision

The measured Canvas symbol label loss requires a narrow Textual owner child of
b940433c7a55b82a8bbbe6fb0837df7162307dbb. Add an opt-in immutable attachment
accessibility descriptor (caller-localized label, optional caller occurrence UUID
and localized action name), default nil on Attachment and forwarded by
AnyAttachment. A type-erased wrapper supplies the descriptor without changing
actual attachment body/metrics/PNG or legacy math factory behavior. Add a Textual
view modifier accepting a main-actor callback for descriptor IDs. No source offsets
are inferred or executed inside Textual; the app owns exact-source authorization.

Drawings remain the existing Canvas. A separate hit-testing-disabled accessibility
layer derives one semantic element per opted-in actual Text.Layout run, positioned
at the same origin and typographic bounds. Only positive finite geometry is used;
no second glyph renderer or pointer interception is introduced. Default nil
descriptors preserve other attachments and legacy accessibility behavior. Native
tests must expose the exact opt-in inline label/own element and custom source
action, retain host/standalone/both-neighbor controls, and invoke the actual native
action to prove the correct UUID reaches the callback. Distinct duplicate formulas
need distinct occurrence descriptors, wrapped-line geometry must remain inside
the owned window, and non-opt-in baseline still records its measured behavior.
The original bounds/timeouts are not weakened. Only hosted native execution is
allowed; owner font/license files and unrelated parsing/selection code stay intact.

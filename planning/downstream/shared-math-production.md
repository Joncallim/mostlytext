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

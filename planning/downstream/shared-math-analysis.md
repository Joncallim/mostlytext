# Admit equations once from an immutable original-source parse

## Owner outcome and baseline

Preview and Export need the same intended equations, original source positions
and unchanged TeX. This unit makes Math own structural admission and renderer
source projection using the merged MathSyntax grammar and qualified parser facts.
It prepares values for both real adapters; neither production consumer switches
independently. Final parity, diagnostics, navigation, accessibility and visual
acceptance remain required after adapter integration.

Baseline main3336e59be56727693ab35f55a975aaf5562a48a5 includes shared grammar.
The stable source-fact predecessor is PR85 exactheadd4b9a30af7c1191054b4ef4f3db348559bd1fae2
with immutable corrected cmark/Markdown pins. PR85 must pass its new complete CI
and merge first. Existing source APIs and source/coordinate adversarial fixtures
have been inspected; runtime behavior overrides the earlier line-mask proposals.

## Ownership and dependency direction

Add the existing local ../MathSyntax package/product to MacDownKit Math. No new
remote package or pin is allowed. MarkdownEngine remains the sole Markdown AST
owner; add only a public exact-source binding query using its existing digest
implementation. Math consumes immutable facts and the raw grammar. Preview and
Export will consume MathAnalysis at their edges in the next integration unit;
Textual does not depend on MacDownKit. Contributing/renderer interfaces, native
views, selection/editing, file authority and existing old math paths stay intact.

## Values and exact-source interfaces

MathAnalysis.analyze(source:document:sourceIdentity:maximumSpanCount:) throws a
Sendable immutable MathAnalysis containing source identity/SHA256, parsed revision,
ordered equations and the grammar's literal-tail offset. The snapshot UUID is
caller-owned per accepted document lifetime/generation; never use it as a renderer
cache key. Verify exact source bytes against MarkdownDocument and source-fact
SHA256. Unbound models, mismatched source/facts, unavailable facts and invalid
prefix mappings fail closed without guessing or parsing again.

Each MathEquation has the original MathSyntaxSpan, a stable occurrence UUID,
rendererExpression and immutable expression segments mapping rendered UTF-16
ranges back to original UTF-16 ranges. Derive occurrence UUID deterministically
from snapshot UUID, exact-source digest, full range and style with a domain-tagged
SHA256 prefix. Repeated equations have distinct IDs; repeated analysis of the same
snapshot has the same IDs. Different lifetime/source bytes cannot borrow an ID.
These IDs are ephemeral source identities, never serialized cache or document data.

## Structural admission and renderer projection

Use one MathTokenizer.scan over the complete source with parser-projected inline
regions. Exclude actual inline code/HTML/images and all link syntax outside its
label. Autolinks are wholly literal. Keep each table cell/block independent and
never pair delimiters across literal/link destination barriers. Thus `$[x](y)$`
is literal while `[$x$](/target)` admits its label equation. Reference definitions
and generated TOC text have no authored inline region and cannot become math.
No replacement text, Unicode normalization, search by expression or second parser.

Preserve original SyntaxSpan expression/full/body ranges exactly. Build renderer
TeX by removing only complete parser-recognized continuation-prefix ranges inside
each body; retain every newline (including CRLF/CR), comment and genuine TeX `>`.
A partial prefix/body overlap is invalid metadata, not permission to trim it.
Produce kept expression segments in source order. Diagnostic mapping accepts only
valid scalar/whole-terminator boundaries; a boundary between kept segments maps
to the following kept source character, and renderer end maps to original body end.
Never derive source positions by searching repeated decoded expressions.

## Execution, limits and failure behavior

This synchronous pure analysis belongs on a caller-owned bounded analysis worker,
never as heavy work in a SwiftUI body. Check cancellation on entry, around binding/
tokenization/projection, periodically during projection, and before returning.
Cancelled analysis cannot publish a partial value. Future app integration must
bind publication to current lifetime/generation and enforce one active/one latest
pending request; this unit does not invent a second scheduler or activate a view.

The caller supplies a required nonnegative maximumSpanCount. Honor the shared
grammar's literal remainder without a second tokenizer. The current256 Preview
per-block limit and100-equation performance corpus are different facts; no implicit
100-equation product cap is introduced. Source/renderer byte caps and render-work
budgets remain app/renderer policy for the adapter unit. Complexity is source
passes plus interval sorting and a monotonic prefix/span sweep; avoid a complete
source buffer or scan per region/equation. Store original/decoded strings and
segments only for admitted bounded spans. No I/O, network, rendering, shell,
filesystem authority, editor/save mutation or user-facing string is introduced.

## Tests, integration and completion

Use Swift Testing on actual ParseEngine plus MathSyntax/Math source. Cover prices,
escape parity, malformed recovery, code/fences/HTML/images, reference/inline links,
table/block barriers, nested/variable/lazy prefixes, Unicode and LF/CRLF/CR,
source/fact transposition, unbound/NUL inputs, repeated equation identities,
source-generation changes, caps, cancellation, TeX comments and every kept-segment
mapping including EOF/surrogate/CRLF rejection. Assert exact authored bytes as well
as semantic values. Keep all original Math and parser tests unchanged.

Execute only an inspected isolated Foundation/C fixture with CoreGraphics CGFloat
as a scalar value (no drawing), exact production source/resources and immutable
remote parser pins plus the local grammar. Run Debug/Release; compile actual Math
and app test targets; inventory/316 Compliance/full format/strict lint; full hosted
package/app tests and all four Debug/Release app/mostlytext builds before merge.
Reconcile actual main's merge tree and all24 remote pins with PR85. No local
AppKit/SwiftUI/WebKit/product CLI or signing execution. This API alone checks no
production math acceptance box; actual native adapter/Export parity, structured
engine diagnostics, accessibility/navigation/cache/worker budgets and final visual/
VoiceOver evidence remain. Stop and revise if exact parser facts cannot represent
a required case or integration requires changing those ownership boundaries.

# Preserve exact Markdown source facts for shared equation admission

## Owner outcome and baseline

Equations must keep their own original source positions without changing link
identity or treating code, URLs or generated reference definitions as math.
Build generic immutable source facts in the existing Markdown parser, then let
Math consume them. This unit adds the parser projection; production Preview and
Export keep their current behavior until shared analysis and transport qualify.
Baseline main is e58240320e5a0a69fa83d15d4d767ab9bdcd14e1; this branch includes
PR84's exact prepared grammar a5c76950bc2279f009f7f176c3027a89d5c98568, which
must pass and merge first. All existing remote pins remain unchanged.

The pinned Swift Markdown 0.8.0 Foundation/C spike resolves three assumptions:
columns are one-based UTF-8 bytes, table cells require precise separate regions,
and Link.isAutolink is a heuristic that also returns true for a bracketed link.
Original syntax and the actual parsed link both participate in classification.

## Ownership, interfaces and invariants

ParseEngine.swift remains the only Markdown importer. Its existing bounded
serial parse owns AST traversal, on its existing large-stack worker. Export only
Sendable value facts: paragraph/heading/table-cell original UTF-16 regions,
literal inline code/HTML/image ranges, parser-recognized continuation prefixes,
and resolved links with full and raw label ranges, target/title and reference
key spelling. No AST, mutable parser, extra parse or renderer crosses this edge.
Bind facts to the same complete-source SHA256 as MarkdownDocument. Manually
constructed documents default to nil facts. Invalid/missing coordinates or
unsupported deep structures fail closed with nil facts; a future Math consumer
must preserve literal source rather than guess positions or silently reparse.

Collect all requested parser endpoints, deduplicate/sort and walk original
Unicode scalars once. Resolve only actual scalar boundaries; do not allocate a
per-byte dictionary. Treat CRLF as one line terminator and reject columns inside
UTF-8 scalars or either terminator. Front matter is never an eligible region;
body-relative parser lines are translated to original lines before resolution.
Use descendants' inline envelopes instead of trusting oversized block ranges. Image alt content stays literal. Code/HTML blocks
have no eligible inline region. Inline code and HTML tags are scan barriers.

Each parsed link label is its own math region. Its surrounding brackets,
destination/title/reference suffix are barriers, so math cannot cross into or
out of a link. This makes Markdown link syntax authoritative: `$[x](y)$` stays
literal, while `[$x$](/target)` admits only its label equation. This deliberate
precedence follows the handoff's destination barriers and will be locked before
activation. Preserve full/shortcut/collapsed reference keys from raw source;
never derive them from decoded Text or compare destination strings to infer
syntax. Only parser-recognized links can obtain resolved-link metadata.

Continuation prefixes come from the first actual inline source location on each
subsequent container line. They are coordinate facts, not exclusions: a display
span may contain them, and Math's later renderer projection removes only these
ranges while retaining original newlines and a decoded-to-source segment map.
Do not strip arbitrary `>` operators or normalize authored equation bytes.

## Failure, resources and integration

The new projection is synchronous within the existing parse request and gains no
filesystem/network/rendering capability. Existing queue/cancellation/lifecycle
ownership remains unchanged. Iterative bounded-depth traversal avoids adding a
new unbounded recursive walk. Cost is one source scalar pass plus endpoint sort
and linear AST/range work; storage is proportional to nodes/endpoints, not every
source byte. No whole-editor latency claim follows from component timing.
No new UI strings, persistence, editor mutations or package dependencies.

Expected files: MarkdownDocument.swift, ParseEngine.swift, new Foundation-only
source fact/coordinate values and MarkdownEngineTests. Verify the exact production
module in an isolated Foundation/C SwiftPM fixture with the pinned Markdown/Yams
sources and existing MarkdownEngine tests, Debug and Release. Exercise Unicode,
CRLF/CR/LF, front matter, nested quotes/lists, tabs, table boundaries, escaped and
formatted reference labels, code/images/HTML, missing block ranges, deep trees,
malformed source and invalid endpoints. Compile the actual application targets,
run normal hosted package/app tests, all four builds, pins and Compliance.

This unit is complete only with exact-source tests, full hosted CI, review and
verified merge. It does not check issue9 grammar/parity/navigation/VoiceOver or
final-app criteria. Next unit consumes the facts in Math with the shared grammar
and immutable analysis; the qualified actual Textual factory/transport remains
the Preview edge. Stop for a focused architecture revision if exact parser
coordinates cannot represent a required authored case without guessing.

## Pinned table-coordinate counterexample

The executable test found that an immediately preceding paragraph loses BOTH
its block and Text ranges. Header cells are assigned impossible previous-line
columns (for example column10 on the six-byte `before` line). Descendant
envelopes cannot repair missing or contradictory inline positions. Retain the
failed first test and raw AST evidence; this unit explicitly returns nil facts
for that source, preserving existing production behavior because no consumer
has activated. Before production shared analysis can activate, qualify a narrow
source-preserving fix at the actual cmark table owner, or revise the integration
with exact independently verified coordinates. No text-search guess, duplicate
parse, weakened source assertion or silent old-tokenizer fallback is permitted.

## Focused revision: qualify actual parser provenance before adoption

The broader review also reproduced wrong-but-in-bounds positions after varying
indentation and lazy quote/list continuation. Bounds checks alone cannot prove
source identity. Keep the prepared PR85 draft while correcting the actual owner.
The qualified correction is now Swift cmark fork
2a5339b89b219584c8fa6c6fd378d3898eed5d57, consumed by the metadata/test-only
Swift Markdown child abfafeccd6f0434daf1a667b92d227adb83b50c8. These are the only
two remote dependency changes permitted by this revision. Original complete
COPYING, LICENSE and NOTICE are unchanged; all87 Swift Markdown runtime source
files and162 unaffected original cmark files are byte-identical to their bases.

The cmark owner records sparse original byte-position segments while consuming
block text, including tab expansion, reference removal and table extraction/
escaped pipes. It corrects inline metadata only after parsing finishes, preserving
delimiter/reference calculations. Public opaque-node APIs remain unchanged;
internal node layout changes and all consumers build from source. The original
runtime fails53 coordinate assertions. The candidate passes them, all668 original
C API controls normally/AddressSanitizer/UndefinedBehaviorSanitizer, exact strict
670 CommonMark/26 regression/30 GFM/16 smart punctuation outputs, and299 XCTest
plus6 source-coordinate Swift Testing functions Debug/Release. One snapshot's
closing-brace column is corrected against an independent authored-byte oracle;
no bounds, assertion or timeout is relaxed. All9054 generated actual AST/format
and HTML cases preserve every non-position byte, including under AddressSanitizer.

Original PR85 hosted CI42002905284 passes, but applies to the earlier source and
pins: it cannot qualify this correction. Keep those logs, then require a new
complete hosted run on the final corrected head. The actual first-party source
fixture now passes158 tests Debug/Release with positive paragraph/table and
variable/lazy continuation assertions. NUL input remains readable original source
but returns nil source facts because parser sanitization is not original-byte
provenance. Unsupported deep/invalid mappings also remain fail-closed.

Baseline actual main is now3336e59be56727693ab35f55a975aaf5562a48a5 after verified
PR84 integration. Reconcile by actual git merge-tree without resetting newer
source. Retain all old failed/green receipts and a proof that the other22 remote
pins, Textual9077b0f6, Neoncd14f22a and both parser geometry policies stay exact.
Production math consumers and final native acceptance still do not activate here.

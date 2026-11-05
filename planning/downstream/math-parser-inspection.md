# Bounded math parser inspection

## Owner summary

Math diagnostics must describe the actual local renderer's interpretation of the
source. The current engine incorrectly typesets percent comments and hides its
existing parse errors. Correct its lexical comment handling and expose a bounded,
Foundation-only inspection of equation bodies. This is a prerequisite for the
shared Preview/Export adapter; it does not activate that adapter or complete #9.

## Baseline and reconciliation

Main f362b61b759068bdcbebf79749dbfdf92a47e82a has shared source-bound MathAnalysis
but both production consumers still use their old paths. SwiftUIMath is pinned
to upstream 0b5c2cfaaec8d6193db206f675048eeb5ce95f71. Its actual parser's original
114 syntax tests pass in a Foundation-only fixture; three new assertions prove
percent comments are incorrectly rendered under LF, CRLF and CR. The fixture
setup failures and first real failures are retained separately. The existing
structured parser codes are authoritative; no second TeX validator is permitted.

## Contract and ownership

A narrow Joncallim/swiftui-math child owns the correction. Preserve every font,
licence and unrelated source byte. A Textual metadata child changes only that
engine dependency owner/revision so the complete graph resolves to one instance.
First-party compliance records identify both changes and the unchanged licences.
No remote document renderer, new native executor or source write is introduced.

`Math.inspectBody(_:limits:) throws -> BodyInspection` runs only the existing
parser, without fonts or SwiftUI execution. It accepts authored equation bodies,
with delimiter auto-detection explicitly off. Outcomes are valid, invalid with
existing error code/message and original-body UTF-16 cursor, internal failure,
or resource limit (input, recursive depth, parser steps). Cancellation throws
CancellationError and takes precedence over a partial parser result. The public
error types are immutable Sendable values; no mutable atom tree escapes.
This unit does not issue a render token or change the old String rendering APIs.
The future adapter must use body mode consistently at rendering as well.

Limits are required at each call. Configurations must have positive values,
maximum input no greater than 1 Mi UTF-16 units, recursive depth no greater than
128, and parser character-consumption work no greater than 1 million steps.
Invalid configuration throws a distinct error before parsing. Every character
consumption (including lookahead) spends work; recursive entry checks depth.
Comment scanning checks cancellation periodically and is bounded by input size.
These are parser safety ceilings, not whole-app performance claims or the final
product equation admission policy. Existing String API behavior remains compatible
except the intended comment correction; it is not newly advertised as bounded.

Bare percent through the next LF/CRLF/CR, including that comment-ending newline,
is removed only from the private parser input, with a sparse original-offset map. Odd backslash parity escapes percent; even parity starts a
comment. Preserve all original body bytes and all non-comment line endings. Scalar scanning handles combining/Prepend neighbors.
The old String parser preserves its existing delimiter detection, then applies
the same comment correction. Raw-body inspection applies it directly to the
complete authored body.
A masked-space approach is rejected because spaces would become visible inside
text commands. The offset map records each removed source range at its resulting
parser UTF-16 boundary; right-biased lookup maps following tokens to their exact
original positions, with end-of-input mapping to original body end.
Raw-body inspection never strips inner dollar delimiters or trims source.

Comment boundaries terminate command names without adding visible spaces; the
boundary indices are indexed once in a scalar walk, avoiding repeated prefix
UTF-16 scans while parsing command characters. See Knuth's TeX82 control sequence
scanner, sections 354-356: https://tug.ctan.org/info/knuth-pdf/tex/tex.pdf.
The preimplementation comment-removal candidate incorrectly joined command names;
three failing LF/CRLF/CR assertions are retained before the boundary correction.
The same adversarial scope also proves and fixes an original truncated cfrac
optional-alignment out-of-bounds assertion. Missing alignment/closing bracket
becomes the existing characterNotFound error, retaining all valid controls.

## State, failures and concurrency

Inspection is synchronous, nonisolated, cancellable Foundation work intended for
the future bounded worker, never MainActor rendering. Each invocation owns its
parser and counters. A limit/cancellation cannot be misreported as malformed math.
The first parser error retains its exact code/message and cursor; a final missing
brace reports end-of-body. Positions are scalar boundaries, original UTF-16, not
Character counts. No document-generation publishing or UI state is added here.

## Verification and adversarial corpus

Before/after actual parser tests cover all three line endings, EOF, escaped and
even-parity percent, comments containing delimiters/invalid commands, comments in
text commands, Unicode around percent and exact original-offset preservation.
Inspection covers every structured error family available in the corpus, original
UTF-16 offsets including emoji and CRLF, raw-body versus old auto mode, empty and
valid input, depth/step/input boundaries and cancellation. Original upstream
syntax tests remain unchanged and execute in Debug and Release. Compile the actual
native module and run hosted complete package/app/build CI; do not execute local
AppKit/SwiftUI/fonts. Preserve original failures and all evidence. Native visual,
VoiceOver, final Release and exact signed-artifact results remain open in #9.

## Slices and completion

1. Correct/comment-test the exact dependency; expose and test bounded inspection.
2. Pin immutable engine and Textual metadata children; reconcile inventory,
   notices/SBOM, patch evidence and licence hashes; compile actual targets.
3. Pass complete hosted CI, review exact head and merge into current main; update
   #9 with scope and re-audit all open issues. No math acceptance box closes merely
   because this prerequisite passes.
Stop and revise this architecture if another renderer or mutable public AST is
needed, parser semantics outside comment handling change, or passing requires
weakening existing assertions. Accessibility/localization have no new UI strings
in this unit; raw parser messages are technical values for a future localized
first-party diagnostic adapter. Export remains on its existing renderer pending
joint production activation.

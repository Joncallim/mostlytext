# Reuse immutable capture names during highlight queries

## Owner summary

Highlighting repeatedly splits the same immutable capture names for every match.
A narrow owned-copy experiment reduces the query portion of the actual one MB
Markdown fixture by about 17%, with identical ordered highlight values. Carry
only that demonstrated private cache into the existing dependency fork. This
is a performance improvement to verify, not a product-budget or parser-abort fix.

## Baseline and readiness

Live main is 4fda20fe5e7ba79b756a3b4bac97db284ebe0933. SwiftTreeSitter is
0beea992c4246f93a122de846c8611c9be19aeb7, Neon cd14f22ae8f8402b175a0bafd87560b78c7549e9,
and tree-sitter remains 5ce80b6f0e29096a5f06826a3ba610c4e89bc255.
PR101's full Release selection at d9c3cc70 fails fullHighlight1MB at
526.371375 ms > the unchanged 500 ms ceiling. Its fresh-process unchanged
performance suite passes, which is diagnostic data rather than full acceptance.
The original parser-only 400 ms and product keystroke/main-thread gates remain.

A vetted Foundation/C-only standalone executable uses the actual pinned Swift
parser, actual block grammar/query and unchanged 1,000,008-byte fixture. Five
baseline passes produce 23,256 captures each, about 183–194 ms parsing and
68–70 ms querying. Eight alternating before/after process pairs (24 measured
iterations each) with immutable capture names/components precomputed once give
median query 69.380 ms ->57.635 ms, with exact ordered NamedRange JSON equality.
Total local medians 254.043 ->243.055 ms are not hosted/product budget evidence.
An additional metadata cache gives no material query gain and is rejected as
unnecessary scope. Original runs and the setup/compile failures remain retained.

## Ownership and permitted changes

Query owns immutable capture descriptions for its immutable compiled query.
Compute optional original name and its existing Foundation component split once
at successful construction. QueryCapture may reuse those arrays by value, with
normal copy-on-write isolation. Keep the direct-name initializer's existing
behavior and public captureName API. Do not cache tree/node/range, change sort
precedence, predicates, metadata/last-wins rules, capture order or Unicode text.
Use only immutable Sendable values; no new unchecked conformance, lock or global
cache. Queries retain the extra bounded per-query metadata only for their own
lifetime. Empty queries and unnamed internal captures preserve existing behavior.

Publish one descendant revision in the existing SwiftTreeSitter fork, and one
manifest-only Neon child so every exact requirement agrees. Update the app and
vendored Markdown manifests, only those two of 24 pins, and matching compliance
inventory/notices/SBOM/patch provenance. Original BSD texts and all other source,
C runtime, grammars, queries, resources/fonts remain byte identical. No new
package family, upstream submission or source-offer publication.

## Slices and proof

1. Preserve the measured original/candidate text-only experiment and explicit
   immutable-source/executable/no-GUI-linkage receipts. Reject the metadata-cache
   expansion; qualify the final names-only source against the same named/global,
   duplicate-key-last-wins and injection-depth controls.
2. Add real-query semantic regressions for multiple named/global directives,
   source/range changes while reusing one query, and concurrent independent
   cursors over immutable trees. Test public values, not private cache layout.
3. Keep all existing tests and thresholds. Require whole app/package CI and
   complete Debug/Release editor/highlighter/theme selections, including these
   three new functions. Adjust the exact required totals to include new tests;
   do not exclude existing tests. Full normal CI retains all app/mostlytext
   builds and app/UI compilation. Preserve every original failure.
4. Include the documented standalone export-sheet ARC fixture correction from
   d9c3cc70, with its existing panel assertions/deadlines. This adds no product
   window policy or historical crash-cause claim. Reconcile actual merged main
   if another independent unit lands before final qualification.

Only after fresh exact-head required checks, source review, unresolved-thread
inspection and merge-tree/parent proof may the unit integrate. Keep required
fork revisions reachable for immutable pins. No local app, public CLI, test
helper, AppKit/SwiftUI/WebKit/font/drawing/signing execution. Local work is
compile-only or inspected Foundation/C standalone probes; native suites are
hosted macOS 26 only.

## Limits and stop conditions

The original parser assertion, memory/lifecycle, production resource routing,
owner-native and exact signed RC gates remain open. No performance threshold,
job deadline, assertion or selection is weakened, and there is no unchanged
retry-to-green. If output/metadata/order, public APIs or source ownership differ,
stop the optimization rather than silently redesigning query semantics. A
whole-suite failure remains failure even if a smaller fresh process passes.

## Integration with the merged model probe

Actual main c249d6db includes PR103's qualified model repair and a focused
before/after probe. That probe's original safety rule rejects every unrelated
pin difference from its frozen 4fda baseline. The two deliberately reviewed
runtime revisions in this unit would therefore fail orchestration even though
both actual model controls and phase-specific immutable locks remain valid.

Extend that rule only for the exact already reviewed pairs:
Neon cd14f22a ->72174c8d and SwiftTreeSitter 0beea992 ->f2163a8b, retaining their
existing canonical owners. Every other additional owner/revision/pin removal
or addition remains rejected. Record the exact independent deltas in the
artifact and require separate source/inventory review; they do not count as
model repair. An unchanged original Textual still produces baseline-only proof
and cannot qualify a candidate. Keep original Textual owner enforcement,
per-phase exact 24-pin equality, frozen original model, identical four tests,
all original assertions, 900/600/660-second bounds and full original failure
requirements. Add pure negative controls for unreviewed revisions/owners/pins
and the baseline-only distinction. No model fixture or production code changes.

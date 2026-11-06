# Avoid comparing the contents of an identical shared subtree

## Owner summary

Markdown parsing can repeatedly compare the same immutable child tree with
itself while resolving ambiguous parses. Avoid traversing those identical
children again. This is the previously measured, unqualified E1 experiment from
the H5 investigation, now to receive current-source regression and full parser
qualification. It is not a new parser design or proof of the 50 ms keystroke
budget, and it does not classify the historical Debug assertion.

## Live baseline and readiness

Actual main is d607098bdb5046c02d81137b497e0ffe1aa01748. Its immutable runtime
is owner fork tree-sitter 5ce80b6f0e29096a5f06826a3ba610c4e89bc255 (0.25.10
plus the already-qualified included-range seek); SwiftTreeSitter is f2163a8b
and Neon72174c8d. Keep every prior correctness repair and the 8,192-unit native
highlight fallback. PR101 source c3a1516b still fails the original direct-parse
400 ms guard at402.177209ms, despite strict replay and Debug passes. Retain that
failure; do not retry unchanged source or claim this optimization addresses its
specific cause before evidence.

Read planning/h5-dependency-followup.md and its h5-profile evidence. E1 reduced
comparison visits from151million to5,454 in the historical256KB inline-dense
fixture, but no full parser suite was run. Those historical measurements use
older dependencies and are motivation only. Current required evidence follows.

## Ownership and exact change

In tree-sitter's private ts_subtree_compare child loop, skip pushing a child
pair when both children reference the same heap subtree. Identity of an
immutable heap subtree establishes identical symbols, child counts and every
descendant. Preserve reverse traversal and ordering for distinct children,
including structurally equal distinct trees. Do not compare arbitrary inline
bit patterns as object pointers: only admit the identity shortcut when both
children are non-inline. Keep all reference counts, ownership, caller behavior,
scanner state, edit geometry, ranges, timeout, C API/ABI and original licences.
No other runtime optimization, tree mutation, global cache or allocator change.

Use a descendant branch in the existing owner runtime fork. SwiftTreeSitter and
Neon may receive only exact dependency-manifest updates needed for a coherent
graph. Update only those three pins and their provenance/inventory/notices/SBOM;
all other21 pins, original runtime files and licence texts remain identical.
No upstream contact or source/public release publication. Retain immutable fork
branches so current exact pins remain reachable.

## Slices and verification

1. Reproduce the current baseline and candidate using inspected C/Foundation-only
   standalone probes. Compare complete tree shape, byte/point ranges, errors,
   edit/reparse behavior and real ordered query results over Markdown block and
   inline, JSON, Unicode/surrogates, LF/CRLF/CR, empty/error recovery, disjoint
   included ranges and deterministic random edits. Include distinct equal trees
   and unequal structure beside shared subtrees; both ordering directions matter.
2. Instrument only disposable source copies to count actual comparison work.
   Record original/candidate hashes and exact instrumentation. Require a
   deterministic reduction for the current inline-dense fixture and identical
   semantic output; keep timing diagnostic rather than an assertion waiver.
   Counter instrumentation never enters the shipped runtime.
3. Run the complete documented tree-sitter Rust/corpus suite before/after and
   applicable C sanitizer/differential controls. Keep existing failures and raw
   setup logs; no skipped positives or test/deadline change. Inspect actual
   executables for GUI linkage before local execution. Build-only work remains
   allowed for app/native modules; all native execution stays hosted macOS26.
4. Add a canonical public-result regression using the actual app dependency
   graph and retain existing queries/grammar fixtures. Require complete normal
   CI and Debug/Release editor/highlighter/theme selection. Add this regression
   to exact selection counts without removing any existing test.
5. Incorporate any actual merged main changes, review source/licence/object/pin
   differences independently, verify all receipts and source/computed/synthetic
   merge trees, then merge only a fully qualified exact head. Record product
   limits, unresolved original triggers and final owner/signed acceptance.

The merged attachment probe rejects unrelated pins by default. Extend its
reviewed-pair allowlist only after immutable runtime/Sitter/Neon heads exist and
their exact source deltas have been checked. Retain all original model tests,
before-failure requirements, phase-specific24-pin receipts and bounds. Pure
negative controls must still reject every unreviewed revision/owner, removed,
additional or duplicate pin. Such allowance is graph reconciliation, not model
repair or proof of native performance.

## Stop and completion conditions

Reject the optimization if semantics, ordering, ownership, memory/sanitizer or
full corpus results differ. Amend architecture before changing algorithms,
fallback policy, public APIs or test budgets. No per-paragraph parser, widened
highlight admission, parser read-assertion patch or TextKit batching is included.
Local timing gains do not qualify an entire app, resolve PR101's recorded
failure or satisfy #18/#19. Only fresh complete required checks permit merge.

## Continuous C work and ownership regression

Add a small Linux C qualification job alongside the unchanged macOS native and
full app CI. This job verifies runtime behavior and work, not native acceptance.
Fetch only the frozen owner runtime base and the exact candidate runtime and
JSON grammar from the committed24-pin lock, rejecting changed owners or duplicate
identities. Require the runtime product delta to be only lib/src/subtree.c and
the original MIT text to remain byte-identical. Compile the same canonical
candidate C control against both runtime versions; preserve all324 ordering and
ownership checks and compare their complete semantic output. In disposable
source copies add exactly one counter declaration and increment per comparison
pair. The original must fail the explicit four-pair shared-root work control,
and the candidate must pass it. Instrumentation cannot enter the product.

Require an AddressSanitizer/UndefinedBehaviorSanitizer build of the unchanged
candidate runtime to pass the same complete semantic selection. Record exact
application input hashes, all pins, runtime/grammar source identities, fixture
and executable hashes, compile/run output and exit statuses. Each compiler is
bounded to180seconds and each normal standalone execution to60seconds; retain
first failures. Reject a missing result, no-op candidate, extra runtime product
changes, semantic differences or sanitizer diagnostics. A completed job must
verify immutable inputs again. Local execution is permitted only for these
inspected normal C executables with no GUI linkage. Native helpers/app/CLI stay
held; no existing native selection, mutation, baseline, architecture build,
threshold or deadline is removed by this additional job.

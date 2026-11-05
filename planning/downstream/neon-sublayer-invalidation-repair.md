# Invalidate embedded-language ownership after edits

## Owner outcome and baseline

Typing or replacing Markdown must expose the same inline syntax as a fresh
highlighter. Correct parser ranges alone are insufficient when the client still
considers old embedded-language work valid. This unit repairs the existing
client invalidation path, not the separate buffered-style coordinate problem.

Application branch baseline d826cc6ae3640f65cf075de9d863aafeebd4cc88 (PR77,
main5c867c5c at intake). Dependency baseline Neon526a29c48ff1b6e949aa47453f0861f9d7b14858,
SwiftTreeSitter7b914f4f1f91f3ecc60478136786babc6d6555fd, C runtime0.25.10.
PR77 must integrate first. Existing h5-neon-divergence evidence isolates missed
sublayer invalidation from buffer drift; inspect current actual source/tests
rather than transplanting old trace instrumentation. Owner approved targeted
fork remediation and implementation of the remaining-issue plan.

## Contract and interface

TreeSitterClient owns mutation/version and sublayer validity. Keep its public
API and threading unchanged. Every completed root edit invalidates embedded-
language ownership in the current transformed coordinates. Publish invalidation
state before calling external consumers that may synchronously query highlights.
Move existing mutation/version bookkeeping before synchronous parse completion
only if controlled callback tests demonstrate that ordering is required; retain
that evidence. Preserve generation and pending-mutation transforms.

Do not eagerly parse the entire document, change synchronous thresholds or
raise the8192-unit app fallback. Existing narrow validation may resolve needed
sublayers on query. Grammar admission, parser points, font styling, source bytes,
network/filesystem authority and native activation remain unchanged.

## Verification and slices

1. Construct strict Foundation/C-only TreeSitterClient tests using current
   Markdown grammars/queries. Warm the actual client so its prior sublayer set
   is valid, edit through willChangeContent/didChangeContent, then compare
   required-mode captures to a fresh client. Include ordinary and reentrant
   invalidation-handler queries, Unicode and LF/CRLF/CR.
2. Record failing old-source output with the same new tests. Apply only the
   reproduced invalidation/state-publication corrections. Run owned exact-source
   RangeState/TreeSitterClient component suites Debug and Release; copy only the
   pinned Foundation-only Rearrange sources, excluding its AppKit/UIKit helpers.
   No local Neon/AppKit/text-view/product execution is allowed.
3. Publish an exact-base owner Neon revision and update app lock, inventory,
   original BSD correspondence and notices/SBOM. No unrelated pin changes.
4. Host the real app/package/CLI build/tests and strengthen only the repaired
   existing replacement assertion. Remaining buffered-style/native/Release-wide
   failures stay visible; do not remove a known-issue wrapper on speculation.
5. Review exact head/merge tree and update owning issue evidence, then immediately
   audit all open contracts. No whole #6/#18/#19/#17 closure from component proof.

Source geometry, mixed synchronous/background edits and performance remain
measured separately. Existing Debug widened-edit abort is not declared fixed
from this client-only unit. All native EXECUTION_HOLD prerequisites, strict
release failures, original failures and source/archive/app publication boundaries
remain intact.

## Query readiness and publication refinement

A sync highlight query may return nil while inline validation is pending; it
must not return old inline captures as current. Async queries await the existing
validator completion boundary and reject a changed content epoch with normal
CancellationError. Add a package-only validity accessor on the existing
SinglePhaseRangeValidator; public API signatures remain unchanged. Publish
mutation/version state before synchronous parse completion and invalidate the
sublayer validator before external callbacks. Reentrant test observations accept
nil (async work pending) or current captures, never stale nonnil output; retain
all callback snapshots so a later corrected callback cannot hide an early one.

Warm tests wait on a lock-protected provider/completion signal, with a one-minute
test watchdog; they never use timed sleeps. The initial no-warm fixture produced
root-only captures and was rejected after adding a real inline positive control.
Its apparent pass and the subsequent control/compile failures remain setup
history, not product qualification.

## Completion and query-boundary review

The existing queue removes a provider when it starts, so its queue-empty test
can return while that provider is still suspended. A controlled provider gate
reproduces this independently: validationCompleted returns before the gate is
released. Preserve the public signature but track completion waiters against
outstanding validations and scheduled follow-up regions. An empty work queue is
not proof that a result has completed. The package-only validity accessor lets
the client retry required holes after completion without publishing partial data.

The generic provider wrapper also starts root processing before invoking its
async closure. Therefore highlightsProvider must own its existing processing
calls directly, capturing the content epoch first. A reentrant source edit at
initial parse publication must cancel the original query, then a new query must
match a fresh client. Sync queries return nil when processing, inline validation
or a reentrant edit leaves their captured epoch unavailable. Async queries check
cancellation and epoch after root processing, after inline validation and after
the background query snapshot. No generic provider or root-processor contract
changes are required. Provider errors retain existing downstream handling;
CancellationError is an ordinary obsolete-query result, not a fatal failure.

Verification retains the rejected setup controls, the flag-only candidate's two
remaining failures and the initially misplaced epoch check's failed test. A
fresh client with no inline injections must still complete its asynchronous
validation before it serves as an expected-result control.

Readiness validates only the requested indices that exist in the current source.
A query may extend beyond end of file; unowned indices must not keep the async
readiness loop waiting forever. A strict past-end query matches an otherwise
identical bounded query. Empty source and ordinary query failure contracts remain
unchanged. Full component checks include all existing RangeState tests and both
TreeSitterClient suites, with the exact pinned Swift C grammar for stress tests.

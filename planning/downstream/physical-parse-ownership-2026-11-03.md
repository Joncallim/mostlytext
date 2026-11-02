# Keep one physical parser worker per engine

## Owner outcome and baseline

A burst of edits must not create overlapping large-stack parsing threads for the
same document engine. Master 87d8d48b documents ParseEngine as serialized, but its
actor suspends while a newly created thread runs. Actor reentrancy admits another
request, creating another physical thread with a 1 GiB virtual stack reservation.
Cancellation is checked after completion and cannot stop that physical work.
This is separate from tree-sitter's #203 work and cmark's pthread_once diagnosis.

## Narrow architecture

Retain one engine-owned admission slot until its physical thread actually
returns. Queue other requests in FIFO order through throwing continuations.
Remove canceled queued requests promptly; a canceled running request retains the
slot until its existing synchronous work finishes, then returns cancellation.
Recheck cancellation immediately after admission, so cancellation racing a slot
handoff never starts stale work. Cancellation callbacks address a unique request
ID and cannot release a running worker or resume a continuation twice.

Retain existing stack size, document semantics, digests, revision/options binding,
main-thread prohibition and dependency pins. No global worker pool, native UI
execution, interruption of cmark/Yams, new module or public initializer is added.
Internal request/physical-start hooks support actual controlled-thread tests;
production initializers keep them nil. Pending text remains owned by callers'
async invocations; this repairs physical concurrency, not a new input-size policy.

## Verification and stop conditions

First run the actual overlapping-thread negative control with request/start
hooks but unchanged admission behavior. Hold the first physical worker, admit a
second request and observe actual peak physical work. Then require peak one,
including cancellation of the owner while still blocked, prompt cancellation of
a queued request and FIFO progress past it. Join all tasks and release private
controls on every exit. Run the exact parser source corpus in Debug and Release,
strict lint/format, source/hash binding and full hosted validation before merge.
Do not claim native preview budgets, global serialization, cmark initialization
repair or closure of broader #117/#203 from these source controls.

## Observed source evidence

With only request/physical-start hooks and the original admission behavior, the
controls reproduce nine failures: physical peak two both with and without owner
cancellation, canceled queued work starting, and FIFO bypass. The fixed engine
passes all 129 exact MarkdownEngine source tests in 18 suites in Debug and
Release, including the controlled cases and deep nesting/YAML/Unicode corpus.
The first harness attempt retained tests from the separate pending anchor stack
and failed to compile against master; replacing both source and test folders
with exact master-based files removed that setup mismatch. Initial lint caught
three catch-layout violations in the new tests; final strict lint has zero
violations. Dependencies and the existing stack size remain unchanged. Hosted
full-suite/native preview evidence is still required and is not inferred here.

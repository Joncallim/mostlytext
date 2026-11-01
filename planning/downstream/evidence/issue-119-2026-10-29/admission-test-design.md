# Deterministic stalled-probe admission and cancellation design

Status: designed, **not implemented or executed as an admission test**. The callback lifetime regression is executed separately. Current source counts in-flight calls in DocumentFileMonitor+Baseline.trackedObserve, then immediately awaits the prober; snapshotNow directly invokes the prober and bypasses that accounting. Existing stale/retired-probe tests exercise publication rejection or feedback-loop prevention while allowing overlapping calls. Their success does not prove the handoff's one-active plus one replaceable latest pending request or shared four-worker ceiling.

## Admission test

1. Finish the initial bind and observe its acknowledgement, so bind's async stack is gone. A cancellation-insensitive gate prober records every actual entry with immutable binding/request generation, expected URL and revision.
2. Hold event read A inside that prober. Submit S1, S2 and S3 while A is held. A narrow internal request-decision observer or actor-returned decision must acknowledge each request as started, coalesced, replaced or retired, including active/latest-pending identity. Await these positive acknowledgements before asserting counts; a sleep, Task.yield loop or an unchanged count alone cannot prove requests reached admission.
3. After all decisions, assert exactly one actual prober entry remains active and exactly one pending identity equals S3. S1/S2 must never enter the prober. The observer must be scoped to the test and released on cancel; it must not become another retained callback.
4. Release A, await its real completion, reject its stale publication and acknowledge only S3 entering next. Release S3 and assert only the initial and latest accepted snapshots publish. Explicitly drain every continuation in failure cleanup.
5. Repeat the same ownership contract for bind/rebind, baseline update, retry, missing confirmation and snapshotNow. snapshotNow needs an explicit obsolete-waiter completion/cancellation contract: never silently return a newer unrelated request or fabricate missing-file state. Preserve caller revision/lifetime checks.

## Cancellation and shared workers

Hold A and acknowledge pending S3. Cancel while retaining the monitor: clear pending work, revoke publication and release callbacks/installed handles immediately. Running cancellation-insensitive A must still occupy its real worker slot. Once A drains, no pending call may start and old watcher ingress/publication must be rejected. Rebind must not revive A. Use positive closure/handle/drain acknowledgements, not an arbitrary quiet-time wait.

Across at least five monitors, positively acknowledge four shared-worker admissions and the fifth pending decision. Cancel a running waiter: it must not free a worker until its underlying call drains. Check queued generation again before entry and completed generation before publication. Use bounded gates and deterministic cleanup, with no real user files or unbounded event storms.

The existing completed callback test proves distinct observation/health/context closures release on cancel while the monitor remains alive and a retired worker is held, then proves stale ingress/publication is rejected after release. Its watcher cancel counter is not an operating-system descriptor inventory and it has no pending-queue/shared-worker assertion. Keep that narrower evidence intact.

## Remaining execution gates

Implement the handoff's bounded admission within its allowed FileCore/narrow asynchronous snapshot area, then run this design, snapshotNow caller-contract regressions, the existing monitor/recovery/save coverage, optimized storm/lifecycle measurements and the real UI matrix. Do not replace the six genuine ExternalFileChangesUITests with injected-controller tests. One/10/50 native-window descriptors, idle activity, same-parent identity search and MainActor conflict/close I/O remain separate measured gates.

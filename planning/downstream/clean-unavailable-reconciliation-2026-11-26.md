# Reconcile clean documents after temporary backing failures

## Owner summary

A clean open file can become briefly unreadable during an external writer's
replacement. MostlyText already keeps the last text recoverable and asks before
closing, but the next readable version is treated as a conflict even when the
user made no edit. Preserve the safe close behavior while remembering whether
the cached text was clean when access failed. A later readable file can then
reload normally if that exact cached text is still unchanged. A local edit must
continue to conflict with a different disk version.

## Current source and contract

The implementation baseline is main `d60daae8362e55092c0139a4e144695677a3e915`.
`FileDocument.markingBackingUnavailable` changes a clean document to dirty so
recovery and close protection remain active. `reconcilingExternalSnapshot`
therefore takes the dirty/conflict path when a temporary read failure is
followed by a changed disk snapshot. `TabStore.restoreFileTab` similarly sees
the saved recovery text as an unsaved edit after a relaunch. This is a source
correctness slice under #17, consumed by #12's later native external-file
matrix. It does not change watcher timing, filesystem authority, the selected
root, or the final candidate requirement.

The previous documentation's description of a transient read failure was a
lead, not acceptance evidence. New tests first failed at both live and
relaunch state machines before implementation. The independent review then
found that the proposed persisted text hash could discard an authored edit
after an `X → Y → X` sequence and a stale session write. The initial failures
and the rejected design remain in the review record; only the live-process
repair is admitted here. Relaunch keeps its conservative recovery behavior.

## State and ownership

`FileCore.FileDocument` owns a process-local copy of the text that was clean
at the first unavailable observation. Swift's String value copy shares
storage until mutation. The unavailable transition still marks the document
dirty and retains recovery. Repeated failures retain the copy only while text
remains exactly equal; an editor transaction clears it, including a no-op
edit. A changed readable snapshot reloads only if the copy still matches the
current text. The accepted snapshot clears the copy and becomes the new disk
baseline. No digest is calculated on the UI actor.

The copy is deliberately absent from `Workspace.TabRecord`. A restarted app
cannot prove that a recovery file with the same text came from the same edit
generation: `X → Y → X` is the counterexample. On relaunch, the existing
dirty/conflict and recovery path remains in force. This may ask the user to
resolve a false conflict after a transient read failure spanning relaunch,
but it cannot silently discard a later authored edit. Resolving that case
requires a durable recovery mutation identity and its own architecture/review.

Disk snapshots, source text, encoding, BOM, line endings, selection, undo,
and rooted read/write paths remain authoritative under their existing owners.
This change adds no new capability, network access, or user-facing string.

## Verification and limits

- FileCore: changed disk after a clean read failure reloads; an intervening
  local edit still conflicts. Repeated failures, no-op edits and matching-disk
  reappearance are included in the focused state-machine selection.
- Workspace: the existing relaunch conflict controls remain unchanged. Add an
  `X → Y → X` recovery case to prove the original conservative restore keeps
  the authored text and does not delete its recovery copy.
- Run affected package suites with the committed lock, selected app-controller
  tests, strict changed-file lint/format, ordinary compliance, final-head CI,
  and independent review. The protected installed Release/manual matrix stays
  deferred under #12/#17, so their broad checkboxes remain open.

## Source-bound results before review

The first two focused controls failed on unchanged main: live reload produced
four assertions against `.conflicted` and old text; relaunch produced four
assertions against `.conflict` and retained recovery. The first log is
`/tmp/mostlytext-clean-unavailable-before.log`, SHA-256
`34efeab049db38c5e29d2ddc1c516482fa30a1d3c3bd0c43a09535aaa97c15b5`.
The relaunch expectation was rejected by the independent review's `X → Y → X`
counterexample; it is not claimed as a fixed behavior. The revised FileCore
and Workspace selection passes 27 tests in two suites, including the ABA
protection case. Its local log is
`/tmp/mostlytext-clean-unavailable-safe-suites.log`, SHA-256
`7188a39272c287ffc9a7eda07763bd6ef9bd195ae1437d6304e41f4ec8cf44dc`.

A pinned Debug app and test-bundle `build-for-testing` succeeds after the
mounted controller regression was added; it does not execute that test. Local
build log SHA-256:
`25398265b90d619a54526559b6f470b4850e1b4988be333d5dc6f076c77226a9`.
Changed-file strict SwiftLint, SwiftFormat and diff checks pass. Ordinary
compliance passes. Final-head hosted app execution and full CI still need the
PR result.

The retired hash design would have scanned full text on the UI actor. A local
`NSString.isEqual(to:)` comparison probe (25 iterations each) observed a
shared-storage median below 0.001 ms for 1 and 10 million bytes; separately
allocated equal text took 0.019 ms and 0.203 ms median, with a 0.705 ms
largest 10-million-byte sample. This is a microbenchmark, not whole-app
latency acceptance. The current code copies the String value at failure and
uses the existing exact-comparison helper only on repeated failure or
reconciliation; it does not hash in the controller.

Targeted independent re-review of the revised integrated diff found no
P0–P2 source defect. It verified that the close/recovery prompt remains,
the accepted snapshot clears the local copy, and the ABA relaunch path keeps
the authored recovery text. The mounted app test injects the unavailable
observation at the controller boundary; it does not prove the operating
system watcher delivers every transient error or complete native latency.

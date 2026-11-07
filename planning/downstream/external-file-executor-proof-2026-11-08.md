# Verify external-file snapshot reads stay away from the main thread

## Owner summary and baseline

The editor should remain responsive while external changes are read and hashed.
Issue12 has a separate unchecked requirement that this I/O stays off the main
actor. Current actual main isd7cff043750123aea66e50406884ca73917885af, including
qualified allocation and documentation integrations. No production repair is
proposed: the current source deliberately performs snapshot work in detached
utility tasks. Add a genuine large-file/move regression and an executable
counterexample before considering that narrow row proved. The complete manual,
event-latency, idle-wakeup, write-storm, state-preservation and final-candidate
requirements remain separate and open.

## Ownership, interfaces and data flow

DocumentFileProbe.observe delegates its entire synchronous observation to an
owned detached utility task. SnapshotReader and FileStore synchronously perform
metadata, immutable byte reading, SHA256 and decoding on that same stack. The
real moved-file branch exposes an existing beforeMovedCandidateRead observation
hook immediately before its synchronous snapshot read. App encoding reopen and
WorkspaceModel conflict reads also use detached tasks; inspect and record those
callers rather than claiming all synchronous FileStore clients are backgrounded.

Add one FileCoreTests suite using the existing probe/read hook only. Call the
real probe from MainActor after a genuine same-directory physical rename of
1,000,000 and10,000,000 authored bytes. Record callback Thread.isMainThread under
a lock, verify it ran and every sample is false, and verify actual moved URL,
physical identity, exact bytes/size and SHA256. Test setup uses its own0700UUID
folder; no real document, account preference, recovery store or GUI is involved.
No new production API, hook, dependency, actor, file policy, skip or budget.

The hook is a native stack observation, not a fake reader or assertion about
whether the implementation contains a Task declaration. The filesystem operation,
move search, immutable read/hash/decode and resulting snapshot are real.

## Counterexample and execution boundaries

A hosted-only private controller copies the exact standalone regression into a
small Swift package depending on the actual FileCore product at the checkout.
Keep all24pins locked; build Debug and Release with testing enabled. Run the
new suite against unchanged source, then the same source with only this exact
counterfactual: replace the probe's detached utility task with a MainActor task.
Both real sized reads must detect the wrong execution thread. Restore original
source exactly and run the same suite again. Capture commands, logs, compiler
outputs, original/mutated/restored source hashes, copied test/manifest/pins and
actual helper/test-binary hashes. Preserve every first result and fail on wrong,
missing, skipped, timed-out or partial execution. No product fix is inferred.

Refuse local/optimized/foreign-host execution before filesystem/build actions.
Only the genuine GitHub-hosted macOS26ARM runner account/home/temp/checkout and
repository are admitted. This is a Foundation-only owned test helper, not an app
or GUI launch. Each build and native command is bounded; existing owned lifecycle
controls supervise execution, with no timeout/cancel/force counted as a pass.
Source is restored in finally even if a control fails. No secret/signing access.

## Verification, slices and stop conditions

1. Commit this architecture before code; source-audit actual main callers.
2. Add standalone meaningful real-file regression, private guarded controller and
   same-repository PR/manual workflow. Verify source/Swift parsing/strict style,
   Python/YAML/host refusal and compliance locally, without product runtime.
3. Freeze first publication through first complete native and ordinary full CI
   outcomes. Both configurations must pass original/restored and fail ONLY the
   intended two thread assertions in the counterexample. No unchanged failed retry.
4. Require full package/app CI, all four locked builds, metadata/style/compliance,
   exact reviewed/tested/computed/actual merge identity and source-only scope.
   Reconcile the narrow original row only if this evidence plus source audit
   proves its exact I/O boundary; no full E18 or whole issue closure follows.

No file-digest/event-latency timing budget, idle/power result, whole-app50msclaim,
installed/signing/owner/locale/VoiceOver or final artifact evidence is added. The
move hook samples the synchronous snapshot-read stack; metadata enumeration and
ordinary expected-path reads share the same explicit detached operation by source
inspection, rather than being claimed as individually sampled callbacks. If the
proof needs broader instrumentation or a changed I/O policy, stop and revise this
contract before changing production source. Any native failure stops readiness.

## First SDK compilation failure and local correction contract

Both native jobs42391191720 atfada82cd fail before execution: the Xcode26 SDK
marks Thread.isMainThread unavailable from an asynchronous function body, even
though the test is MainActor-isolated. The complete first native logs/receipts
are retained before correction. FullCI/CLI/Compliance first outcomes remain frozen
atfada until complete; do not publish or execute this local correction before
all four original workflow outcomes are retained. No native phase is inferred.

Read that identical property in a synchronous MainActor helper called directly
from the same async MainActor test, with no suspension in between. Keep the
genuine physical main-thread precondition, not a weaker actor-only substitution.
All actual file sizes, read hook, fidelity/hash/identity checks, counterexample,
owned lifecycle, configurations and limits remain unchanged. This is an SDK
calling-context correction to test setup, not a production I/O repair or waiver.

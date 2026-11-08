# Preserve verified process identity after native app termination

## Owner outcome and live baseline

Main324155cc9cfb45116d32a2a05c2f0d392507ecea uses the hosted-only
native-cli-app-host.swift helper for normal app launch, inspection and identity-
bound normal/force termination. Actual original export first42424848502 on
source734db2f2 proves its record can report PID-1 after termination, although the
command and pre-operation executable/birth verify the correct process. Preserve
those exact first records before correcting this private evidence-metadata defect.
No wrong-target kill, product data loss or normal Quit is inferred from that fail.

The helper will retain the actual verified positive process identifier before
an operation and emit it as stable pid. Emit the actual post-operation property
separately as observed_pid_after_operation, including-1 if NSRunningApplication
clears it. This makes identity-bound evidence inspectable after ordinary Quit.
This is not a product/CLI feature or a signing/native-owner acceptance claim.

## Binding boundaries and interface

Only .github/scripts/native-cli-app-host.swift plus this decision/evidence.
No product, dependency/pin, CLI protocol, runtime authority, app identity, public
command, launch environment, timeout, owned cleanup policy or existing workflow
change. MainActor retains the same NSWorkspace/NSRunningApplication operations.
Launch snapshots application.processIdentifier and refuses nonpositive values.
Inspect/terminate/cleanup snapshot the actual resolved object's processIdentifier
before any operation and require equality to the requested positive PID as well
as the existing exact executable/bundle/birth verification. Merely echoing an
unverified command argument is forbidden. Snapshot precedes terminate/force.

Keep all current operation guards and eight-second yielding teardown budget.
Every original success/failure path remains, including fail-closed mismatch,
rejected/unfinished termination and unknown operation. Inspect metadata stays
permission-conditional: no WindowServer grant or screenshot is inferred. Keep
window limit32/title160 and normal-versus-force operation labels unchanged.
Factor unchanged window read/record emission into small MainActor helpers if
needed to keep strict lint readable. No new production state or workers.

## Tests, evidence, risks and slices

1. Commit decision and exact actual-1 counterexample before implementation.
2. Apply the pre-operation snapshot and explicit post-observation field; inspect
   all existing consumers for schema assumptions. Swift6 strict SDK typecheck
   only, format/strict lint, existing pure host/owned/process guards and compliance
   locally. No local native app/helper/product execution or builds.
3. Freeze and qualify actual hosted ordinary public-focus and warmCLI journeys
   using genuine positives/real PID-birth peer, unchanged source/pins/compiled
   inputs and normal Quit. Independently require every returned stable pid equals
   its original actual launch pid, including termination; retain the actual new
   post-operation observation rather than inventing it. Original failed export
   outcome stays failed. Preserve complete first logs/artifacts before correction.
4. Scoped orthogonal source/native self-review, original issue reconciliation,
   expected-head merge and exact actual parents/tree verification only when ready.
   Refresh the complete repo after every issue update. No broad issue closure,
   installed/trusted cold launch/final signedRC/owner acceptance from private proof.

Stop on any changed authority/target-selection/teardown API or a failing native
journey; revise this decision before changing its architecture. Old receipts keep
original-1 metadata and are never rewritten to the corrected schema.

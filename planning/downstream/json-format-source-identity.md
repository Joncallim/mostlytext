# Reject byte-different JSON formatting snapshots

A Format JSON completion must not apply to a different source snapshot. Its
baseline already checks text independently of generation counters, but Swift
String equality treats canonically equivalent Unicode spellings as equal.
A decomposed JSON string can therefore match a composed source despite having
different UTF-8/UTF-16 coordinates. Make that existing guard compare exact bytes.

## Baseline and boundary

Stable source is PR73 `9b9b5cf2c5e8a94418e0489ca19a9f94880ba659`; main is
`a95ff1fc4498e925eb1582fa6eb9e7fab5baf5ad`. PR72/73 qualification/integration
precedes this dependent merge. MostlyText #17 owns exact-text audit findings;
#8 retains final native/full review acceptance. Inspect the actual app caller
and existing JSONFormattingGenerationRaceTests, which already require a text
change to reject even with unchanged counters.

Only JSONFormattingBaseline.accepts, its comment and focused regressions change.
Compare UTF-8 views directly without allocating Data, preserving all document/
editor generation checks. No new module dependency (FileCore already depends
on JSONSupport), app guard/identity/lifecycle changes, parser semantics, JSON
format policy, resource/pin/UI changes or speculative abstraction. Do not alter
synthesized Equatable semantics or unrelated analysis publication in this unit.

## Verification and limits

Before editing the production guard, reproduce with source-identical JSONSupport
in an owned Foundation-only SwiftPM library/test fixture. Retain exact input/
source/test hashes and old failures. Golden cases use canonically equivalent
but byte-different valid JSON strings in both directions with identical counters;
also retain unchanged positive and changed-counter controls. Run the identical
new tests plus existing JSON suites in Debug and Release, pinned format/strict
lint, Compliance/inventory and complete hosted locked app/package/CLI/build CI.
No local product, AppKit or WebKit execution. No assertion or deadline weakening.

The proof concerns the pure guard's declared contract, not a reproduced native
editor event sequence or every audit finding. Existing generation/lifecycle
protection and native acceptance remain binding. Record all failures, review and
merge exact qualified source, verify actual tree/parents/clean main, update #17
with scoped evidence and reassess all open issues after the update. Stop if a
fix requires a new module dependency, changed formatter semantics or native
lifecycle policy outside the guard.

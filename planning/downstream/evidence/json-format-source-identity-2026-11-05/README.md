# Exact JSON formatting snapshot guard — 5 November 2026

Swift String equality considers decomposed and composed Unicode spellings equal.
The existing JSONFormattingBaseline guard promised to reject a changed source
snapshot even with unchanged counters, but accepted both substitutions. The
new direct UTF-8 comparison preserves exact authored scalar/byte identity and
both generation checks without allocating Data or adding a module dependency.
The actual app caller uses this guard after asynchronous Format JSON work.

[The verification record](verification.json) binds every copied source/test/
resource, command and raw/gzip log hash. The owned library/test fixture contains
unchanged JSONSupport sources/resources and its real suites, using
[the retained manifest](fixture-Package.swift). There are no third-party package
dependencies or app/SwiftUI/AppKit/WebKit targets.

At baseline `9b9b5cf2c5e8a94418e0489ca19a9f94880ba659`, the new pure-guard test
records two real failures: NFC-to-NFD and NFD-to-NFC with identical document and
editor counters. It separately proves that String equality is true while UTF-8
identity is false, and retains unchanged-positive/changed-counter controls.
Fixed source passes all98JSON tests/12suites in Debug and Release. All316
Compliance controls, source inventory, pinned SwiftFormat0.63.1 and strict
whole-tree lint pass. To reproduce, copy each listed source/resource into
Sources/JSONSupport and tests into Tests/JSONSupportTests beside the manifest;
verify the hashes before running the recorded commands. The negative uses
baseline production sources with this revision's new regression file.

This is a failing-before/passing-after proof of the pure guard's contract,
not a reproduced native editor event sequence. The caller, formatter policy,
lifecycle/counter logic, public models, Equatable semantics, dependencies and
native receipts remain unchanged. Whole-app native/Release/exact-candidate
acceptance and the other #17 findings remain open. PR72/73 must integrate first;
full exact-head hosted CI is a separate PR gate. All existing renderer failures
and strict compliance predicates remain unresolved.

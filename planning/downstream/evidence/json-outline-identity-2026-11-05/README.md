# JSON outline identity and source rebuilds — 5 November 2026

Raw dotted paths aliased a literal `a.b` key with nested `a`/`b`, an `arr[0]`
key with an array element, and canonically equivalent Unicode keys with each
other. Separately, the controller's source comparison skipped rebuilds after
NFC/NFD edits and left old UTF-16 ranges. The parser already preserves distinct
Unicode keys; the outline must keep that distinction.

Simple ASCII letter/digit/underscore/hyphen keys retain their existing dotted
IDs. Other object-key segments contain base64 of exact decoded UTF-8 bytes in
quoted brackets; array segments remain numeric brackets. IDs are ASCII and
structurally unambiguous. User-visible titles remain unchanged. The controller
compares optional source by exact UTF-8 and retains existing nil/availability
and true no-op behavior. Collapse/selection IDs are explicitly in-memory only;
no stored state/document format changes.

[Verification](verification.json) binds exact source/test/resource/dependency
and raw/gzip log hashes. The owned fixture combines unchanged Foundation/
Observation-only JSONSupport/OutlineUI/MarkdownEngine sources and actual suites,
with pinned local parser dependencies and [this manifest](fixture-Package.swift).
No app, SwiftUI, AppKit or WebKit target is imported or executed. Export the
recorded dependency commits under Dependencies and copy the listed exact files
to Sources/<module> and tests to Tests/ModelTests; verify hashes before running
the recorded commands. Old negatives use baseline production with the four new
regression functions. Retain actual old failures rather than treating them as
qualification passes.

At baseline `4b190bebe8b3b120305ad6b6a4e2521dec5ca33d`, the four new functions
record 16 real issues. Fixed source passes all166tests/21suites in Debug and
Release, including existing JSON identity/collapse/controller/performance suites.
Goldens verify unique IDs, exact per-ID lookup/collapse, reordered/formatted
identity, equivalent JSON escape spellings and rebuilt Unicode source/jump
ranges with exact-source no-ops. All316Compliance controls, source inventory,
pinned formatting and strict whole-tree lint pass.

Full locked hosted package/app/CLI/build qualification is a separate merge gate.
This component proof does not establish native sidebar/keyboard/VoiceOver,
whole-app memory/latency or all #17 acceptance. Encoding retains proportional
key data; no app resource budget is newly calibrated. PR72/73/74 integrate first.
Existing renderer failures, strict compliance predicates and all native/rights/
publication/exact-candidate requirements remain open.

# Inline injection reconciliation — 5 November 2026

An edit can collapse old included ranges or move a new injection's start. The
old merger only replaces identical starts, so the C parser rejects the new list
and keeps stale input. A second reproduced defect lets a vanished capture survive
when it overlaps no fresh capture. The root tree already equals a fresh parse;
the injection ownership is stale.

The maintained [SwiftTreeSitter fork](https://github.com/Joncallim/SwiftTreeSitter/commit/1b1c85e94df6421a0e4bdcb9f3afaddb16b75d43)
reconciles queried coverage plus complete returned capture extents. A sorted
sweep retains unqueried neighbors, removes collapsed/overlapping/vanished ranges,
invalidates removed spans and retires empty restricted layers. An empty C range
list would otherwise broaden parsing to the whole document. Duplicate captures
are deduplicated; unchanged unqueried layers are not reparsed. Public APIs and
thread ownership remain unchanged. [Final full patch](review-corrected-swifttreesitter.patch).

The [Neon pin update](https://github.com/Joncallim/Neon/commit/e1e0c6de7f299fd8e9ff2b5ecb468d04ee6d50a9)
is manifest-only: runtime/test bytes are unchanged from dabf50c9. App, Neon and
the local Markdown wrapper name one canonical SwiftTreeSitter URL/revision.
All 24 dependency pins are recorded; only these two change. Original BSD texts
match both fork revisions byte-for-byte. No upstream submission is claimed.

## Actual checks

- The original three new upstream regressions record five real old-source
  failures. The first overlap-only candidate leaves three failures in the
  combined-edit case. Both failed outputs are retained; the final tests retain
  that combined case and add root-tree controls, partial queries, neighbor and
  duplicate preservation, vanished and empty restricted-layer retirement.
- All 36 existing upstream XCTest cases plus eleven Swift Testing cases pass in
  Debug and Release at the final source.
- The exact copied application test/grammar/query corpus exercises seven edit
  shapes, two resolution modes and LF/CRLF/CR with Unicode: 42 scenarios within
  one parameterized test function. Final old source records 62 actual assertion
  failures; the fixed source passes Debug and Release without a known-issue
  wrapper. [Results](markdown-final-results.json).
- All 316 compliance tests/source inventory, pinned format and strict lint pass.
  The complete real HighlightingTests target compiles with forced locked
  resolution; it is not executed locally. Existing test thresholds,
  highlighter fallback and Neon known-issue wrappers remain unchanged.
- Initial reproduction failed before compilation because inherited TMPDIR was
  unwritable. A fresh owned task TMPDIR fixed only that harness setup; the raw
  failure is retained. Initial style checks found long new manifest lines;
  wrapping corrections and final checks are recorded separately. Resolver changes
  also made the generated SBOM stale: that real seven-failure strict check is
  retained, the SBOM regenerated, and the final ordinary/six-failure strict
  receipts are separate.

[Verification](verification.json) records compiler, source/test/resource hashes,
exact upstream bases/fork revisions, raw/gzip hashes and the pinned C runtime.
[Fixture manifest](fixture-Package.swift) builds only Foundation/C parser/library
modules. Copy the manifested vendored grammar/resource directories and unchanged
application test into its Sources/Tests layout; point its one path dependency at
the recorded fork checkout and verify hashes before the recorded Debug/Release
SwiftPM checks. The baseline uses the original cbe31cb3 library with the same
final application test/grammar/resource bytes. No local product, SwiftUI,
AppKit or WebKit execution occurs.

## Limits

Full locked hosted application CI is required before integration. Pure layer
success does not establish mounted editor, native geometry, IME, visible styles
or whole-app latency. Neon sublayer invalidation/buffer drift, Markdown grammar
reuse, inline GLR and renderer failures remain separate. Do not lift the
8,192-unit fallback or close #6/#18/#19/#17 from this component result. Six
strict release predicates and native/rights/signing/publication gates remain.

## Final source review correction

The initial app head d826cc6a passed complete CI41961681501 (3451 package
tests/485 suites with two existing known issues,619 app tests/127 suites and
all builds/pins). Before merge, final review reproduced a missing cross-language
partial-query case: one wide capture erased two unqueried narrow captures in
another language. Its actual failed expectation is retained. Expanded coverage
is now requeried to a fixed point before replacement; the added regression
preserves all three captures and a second test verifies retirement when only a
changed language tag is queried outside its body. All36 upstream XCTest plus11
Swift Testing cases and all42 Markdown scenarios pass Debug/Release. The initial
pass is historical evidence, not qualification of this corrected source. Fresh
full app CI is required. Initial patch/logs remain alongside final correction.

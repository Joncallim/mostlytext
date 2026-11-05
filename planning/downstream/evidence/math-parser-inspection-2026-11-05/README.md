# Actual bounded math parser — 5 November 2026

The local fixture executes the actual pinned Foundation-only SwiftUIMath syntax
and helpers, with only the unused outer SwiftUI View namespace replaced by an
empty public enum. It runs no fonts, drawing, native product, AppKit, SwiftUI,
WebKit, product CLI, owner document or signing-key code. All 24 copied source/test
files are exact; manifest.json records the owner revision and SHA-256 of each.
The two original upstream parser/atom suites are unchanged. The two original
fixture-only comment controls remain alongside the owner's new inspection suite.

The first final-debug.log/final-release.log pass 130 tests in four suites.
The final-stress-debug.log/final-stress-release.log supersede that result with
**132 tests in five suites**, including 100,000 deterministic partial equations
and original-source cursor scalar/CRLF bounds.
The corpus covers percent comments under LF/CRLF/CR/EOF, odd/even slash parity,
comments inside text commands, combining/Prepend neighbors, command-name
boundaries, existing structured error families, exact original UTF-16 cursors,
raw-body mode, inclusive UTF-16/recursive/work budgets, invalid configuration,
cancellation and every prefix of eight representative command families under
eight small parser-step limits. Resource exhaustion/cancellation are distinct
from malformed input; no mutable syntax tree escapes inspection.

Original failures are preserved:

- original-parser-and-comments-actual.log: 114 unchanged upstream controls pass,
  but three new line-ending comment assertions fail. The preceding manifest and
  mutating-test-macro setup failures remain separate logs.
- original-truncated-argument.log: the original parser asserts beyond input end
  for the partially typed cfrac optional alignment. Missing alignment/closing
  bracket now yields the existing characterNotFound code.
- before-comment-token-boundary.log: a candidate comment-removal implementation
  accidentally joins command fragments into a valid alpha command; all three
  line-ending controls fail before the indexed token-boundary correction.
- generated-partial-corpus.log and generated-partial-trace.log: the first
  deterministic stress corpus finds an original mismatched radical-degree
  assertion at case 16,182. The minimal original sqrt[} crash is reproduced in
  original-mismatched-degree.log. A guard reports the existing mismatchedBraces
  error before the retained invariant assertion. before-GeneratedPartialInputTests.swift
  retains the exact first trace-producing test. The expanded 100,000-case corpus
  then passes in Debug/Release, including original-source cursor bounds.
- candidate-complete-first.log: two initial test cursor constants are incorrect;
  initial-BodyInspectionTests.swift preserves them. The corrected expectations
  derive independently from original literal NSString prefix lengths. No runtime
  rule or other assertion changed to accommodate those incorrect constants.
- candidate-first.log records an incomplete fixture copy after a read-only-file
  permission error, followed by the old comment failures. The owned candidate
  permissions were corrected before copying all actual candidate files.
- application-resolve.log is an interrupted fresh dependency fetch, not a failed
  test. resolve-interruption.json records why. A verified existing C++ grammar
  mirror was copied into the owned scratch directory; the deliberate resolve
  with skip-update then passed. No global cache was removed or changed.
- Initial format/lint failures on the long new manifest pin remain; the pinned
  formatter corrected the line wrapping without changing policy or checks.

Only original Parser.swift changed in SwiftUIMath. All **96 other original files**,
including every font, licence, snapshot and original test, are byte-identical to
upstream 0.1.0. unchanged-original-files.json records their hashes. The narrow
Textual child changes **only Package.swift** to use the same immutable engine
owner/revision. remote-pin-proof.json proves that these are the only two changed
pins among 24. Owner patches are included; original notices and all font/source
licence hashes are unchanged. Notices and SBOM record the actual new owner.

The actual locked MathRenderingTests target **compiles** locally in 26.94 seconds before the additional stress finding;
the final-stress native target compile log qualifies the seventh regression too.
The new seven-function first-party public-API/native-metric corpus must execute in
full hosted CI, together with all existing package/app tests and four builds.
Local compile evidence is not native execution or acceptance. Full inventory,
330 Compliance controls, pinned format and strict lint of 1,373 files pass.
The logs retain their original bytes under gzip with size/SHA-256 in manifest.json.

This prerequisite does not activate source-bound MathAnalysis in Preview/Export.
Both production adapters still need shared admission, body-mode rendering,
source-anchored localized diagnostics, bounded workers/cache, equation-level
accessibility/navigation and actual parity qualification. No #9 checkbox closes
from the parser API alone. Native visual/VoiceOver and final signed-artifact gates
remain separate and held. See ../../math-parser-inspection.md for the binding
architecture, failure model and next steps.

To reproduce the Foundation fixture, provide an exact local clone of the engine
to reproduce-foundation.py, then run swift test and swift test -c release in the
new output directory. The script reads immutable Git blobs, checks every digest,
and creates only the named Foundation target; it never executes a native product.

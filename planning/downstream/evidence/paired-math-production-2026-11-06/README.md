# Paired production math activation

Base: PR92 merged as `05238f47191e8350f4ace5817a5f6066e1394176`, qualified head
`4ee9681360af6e9f4c63ef7a5e3bbdebe7978805`. The merge parents/tree and preservation
of the uncommitted next unit are recorded. Complete raw CI passes 3,622 package
and 626 app tests; native run 42093505120 passes 46 tests/12 suites. These qualify
the prepared base, not this activation's new app code.

This change registers both production destinations together, preserves original
source through the display cache and binds native occurrences/actions to a fresh
live window/model/editor/parser lifetime. Foundation session/source-planning tests
pass 461 tests/52 suites Debug and Release. Native app and UI bundles compile with
`build-for-testing`; they are not executed in the protected owner account.
Strict SwiftLint and pinned SwiftFormat pass; ordinary compliance passes.

First failures are retained: missing optional source hash caused a compile error;
then test-action linking exposed an undeclared direct Textual product. The same
existing immutable Textual product is now explicit in the app and test targets.
An attempted regeneration initially declared the test dependency twice; a stale
project build then lacked the newly split PreviewPane source. Correct regeneration
and locked test-bundle compilation pass. No native assertion, timeout or product
policy was relaxed. First format/lint findings are also retained.

The added grammar cases initially failed Swift Testing metadata compilation because
a Sendable static fixture was actor-isolated; the fixture is now explicitly
nonisolated and all real app/UI tests compile. These cases require exact-head hosted full CI
and actual native tests before merge. Local compilation and Foundation execution
do not establish owner UI/VoiceOver/visual/PDF, final whole-app calibration or
signed-candidate acceptance. Source-only/compliance publication is unchanged.

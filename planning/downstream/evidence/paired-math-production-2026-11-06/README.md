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

## Hosted base rerun and stronger final controls

The main push run 42101684271 is retained: one original diagram preparation
cancellation test failed before requesting cancellation because a five-second
poll obtained no page. It is not an infrastructure-only failure or a green run.
The binding test correction is `diagram-preparation-test-event.md`: signal actual
preparation, propagate admission failure, retain a five-second cancellation
watchdog and all original assertions, add a never-borrowed assertion, and drain on
setup failure. Production admission/evaluation/retirement behavior is unchanged.
The broader cause of WebKit startup delay/issue #15 remains unresolved.

Native app navigation tests now use the real registered coordinator/editor and
fresh key-window positive controls, then synchronously verify own full/diagnostic
selection, complete secondary-selection reset, stale frame/foreign ID, changed
editor/generation/parser, removed window and wrong-window rejection. They compile
locally only. A focused hosted workflow runs these and actual production grammar/
live-source tests and requires all three named suites to execute successfully;
full CI is still required separately. The new pending Preview tests require the
native MainActor; the first missing annotation compile failure and the macro
unused-result warnings are retained. Explicit Bool observations retain every
assertion and compile without those warnings.

PR93 first head 11d6e289961b70467818ece0b07104386d1c4c94 passes native run
42104288768: 46 tests/12 suites in 3.674s. This qualifies its exact fixture input,
not the following app navigation/preparation changes or a complete production run.
All 24 dependency pins, shipped notices and SBOM remain byte-identical.


## Final scoped review corrections, requiring fresh hosted qualification

The d98c2fb6 focused native run42106201887 fails nine navigation setup cases:
the manually captured session has lost live authority before navigation. The
actual production grammar/failure/reference suite and three live-source controls
pass. Complete run42106201852 passes3627package tests/519suites, then fails those same nine cases in three
navigation functions (653 app tests/135 suites); other app tests and all four
locked Debug/Release builds pass. Neither failed run is described as a pass.

Adapter controls now mount the actual registered TextKit editor before waiting,
separately from independent SwiftUI initial parsing; guards/assertions are retained
and owned fixtures close/dispose on every exit. A separate production app-shell
recovery test preserves the full automatic pipeline and invokes its actual native
attachment action in split and Preview-only layouts. The latter waits for real
attachment before consuming its pending source action. Reduce Motion disables the
custom reveal animation. These native tests compile locally only.

Source planning is explicitly concurrent. Global reference passes honor
cancellation; the actual new regression fails four assertions against the former
code and passes after correction. Per-block content identity preserves unaffected
ordinary native state while including exact source, base URL, parser mode and all
original URL authority. Math markers retain their own frame identity. Native
pending authored blocks have zero URL authority; generated/standalone callers keep
their admitted behavior. A changed target set cannot reuse identical rewritten
Markdown. No secondary math grammar or new resource authority is introduced.

The final exact first-party Foundation fixture passes466tests/53suites Debug and
Release; its current source/test receipt is byte-matching. Actual complete package
and app/UI test bundles compile without local execution; strict lint/format pass
1442files, ordinary compliance and330compliance tests pass. Read-only unsigned
bundle inspection passes; this is not a signed or exact release-candidate proof.
Fresh FOUR-suite app/native46/complete CI remains required for this final source.
The scoped review is by the implementation agent, not independent final release
or compliance acceptance. Owner visual/VoiceOver/PDF/calibration/signing and
source-offer gates remain unchanged.


## Hosted source 9c3d6358: navigation fixtures and app-shell failure

Focused run42115144432 executes12tests/4suites and fails5issues. Both
LiveSource and SharedMathActivation pass. Navigation records3issues: assigning
NSTextView.string itself moves selection; the generation control used identical
updatingText, which deliberately does not mutate. Establish selection after the
mutation and use edited(text:) with a positive generation-change assertion.
No product authority guard changes. The production app-shell recovery also
fails its unchanged five-second presentation deadline. This remains unresolved;
named-stage/source/parser/editor/accessibility diagnostics now distinguish a
missing publication from an inaccessible native attribute. Actual app/UI test
bundles compile successfully locally; native execution remains hosted only.
The failed raw log is retained. Fresh hosted qualification is still required.

The qualified SourceMathAccessibilityProbeTests and SourceAttachmentAccessibilityTests
both initialize the native SwiftUI accessibility client by requesting their own
process role with a0.5second messaging bound. The app-shell recovery test omitted
that request. It now uses the same request and requires successful AXApplication
role before inspecting the native tree; all five-second presentation bounds and
equation/notice/action/selection/remount requirements remain. This source-based
fixture correction compiles successfully locally, with no native execution.
A fresh hosted result is required to determine whether it resolves the timeout.

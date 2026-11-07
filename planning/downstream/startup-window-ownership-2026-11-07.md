# Close only the window created as the empty startup scene

## Owner summary

Startup must remove its own empty SwiftUI window while leaving document,
Welcome, settings, panels and component-test windows alone. Current cleanup
identifies every window without one of three known delegates as a placeholder.
That does not establish ownership. Verify a focused failing regression on a
separate hosted Mac before changing the classifier, then explicitly mark the
empty scene's window and require that mark when cleanup runs.

This is a narrow window-ownership repair. It does not change migration policy,
preferences, document ownership, native tabbing, the startup delay or public
menus. It may intersect the held Preview component failures because those
fixtures create ordinary windows, but that cause is not established. Do not
claim the Preview problem solved without its own unchanged qualification.

## Current baseline and source facts

Actual main ise90127e9f75df20b8be1179e6ba7730651775cb2. PR119 has fully passed
ordinary CI3719/536 package +676/142 app/all four builds, actual normal public
focus and all six public CLI comparisons. Its actual/source/synthetic/computed
tree is05eef5a45171caa1a8cd351550e07b952a94ee1f. PR121 is independently
executing the original named focus case; do not cancel or mutate that first
outcome. Intake its actual merged infrastructure before final publication of
this product correction if it qualifies first, avoiding a stale merge base.

AppDelegate currently closes windows matching isSwiftUIPlaceholder both while
entering migration and in a delayed100ms task after readiness. Its classifier
only rejects WindowController, FirstRunWindowController and
LegacyImportWindowController delegates. A plain NSWindow is therefore claimed
as a startup placeholder. Existing PlaceholderWindowCleanupTests even labels
a plain untagged window a placeholder. SecuredMarkdownMountedTests constructs
an ordinary NSWindow with an NSHostingView and no matching managed delegate;
the predicate cannot distinguish it from its own empty scene. This is a
source-confirmed ownership defect, not proof of the image failure's cause.

## First counterexample, before product code

Add one private source regression extending the existing component test suite:
an owned ordinary unmarked NSWindow must not be a startup placeholder. Use
animationBehavior.none, isReleasedWhenClosed=false and scoped close on exit.
It calls the actual production classifier; no predicate copy, mock window or
test-flag bypass. Keep this exact assertion unchanged for before/after.

On a disposable trusted hosted macOS26/ARM runner, copy only that one additional
test source into the generated root test input. Record canonical sources,
the explicit one-file addition recipe and executed hashes. Product source
stays byte-identical to main for this baseline. Generate/pin the ordinary Debug
project and select only the new component regression with the normal owned
600s wrapper. Require one genuine failed assertion naming the classifier,
zero skipped/expected-failure cases, normal return65, no timeout/cancellation.
Preserve complete actual result/logs even if the hypothesis is not reproduced.

A green counterexample workflow means the old ownership error was observed;
it is never a production pass or merge qualification. This diagnostic stays
draft until the correction and normal required checks genuinely pass. No local
AppKit/native/product build or execution: locally only source/AST/type checks
and guard-only controls. Hosted component execution is separate from native
gesture/complete critical/exact signed-artifact acceptance.

## Narrow correction after the counterexample

The empty WindowGroup content becomes a zero-size NSViewRepresentable marker.
Its NSView's viewDidMoveToWindow explicitly marks only the window hosting that
empty scene with an internal startup-placeholder identifier. Document/Welcome/
migration managed delegates cannot be marked, and remain protected even if an
identifier is stale or mistakenly present. This private window-role identifier
is not a public product/file-type identity.

AppDelegate owns markSwiftUIPlaceholder and the shared managed-window predicate.
isSwiftUIPlaceholder requires BOTH the exact explicit role and absence of a
managed delegate. The existing close sites and100ms timing remain unchanged;
do not replace the policy with a global close, a guessed private SwiftUI class,
test-host exemption, delayed success or preference override. A changed window
delegate invalidates placeholder authority before cleanup.

Update the old positive test to create an explicitly marked placeholder, retain
Welcome protection, add an actual marker-view attachment test, and adopt the
exact original unmarked-window regression into the canonical test target.
After the fix the same regression must genuinely pass; all scoped ownership
tests and complete ordinary CI plus the normal public focus journey remain
required. Add these startup source paths to the separate normal-focus workflow
so future changes requalify the actual public behavior.

## Trust, data and evidence rules

Reuse the already qualified same-repository hosted guard, including explicit
optimized-Python refusal before preparation, real/effective non-root runner
identity, actual macOS26/ARM and exact private RUNNER_TEMP root. Owner/test homes
and Fast SSD must be absent. Never spoof UID, change CORTANA's protected guard,
run its held executor, grant/reset TCC or access a signing key. Ordinary Debug
component testing is intentional, not Release or exact-artifact acceptance.

Capture complete canonical/executed manifests,24pins, actual generated inputs,
actual app/test configuration and hashes, original command/result bundle and
owned outcome. The extra regression is the only baseline derivation. Restore/
verify all canonical bytes and preserve evidence outside any cleanup. No global
process termination; only the owned wrapper's exact app identity may be cleaned.

Stop on unexpected test counts, unrelated assertions/crash, zero-case execution,
source drift or inability to reproduce the wrong classification. If the narrow
marker cannot be observed on the actual scene, revise the architecture before
changing policy. Do not blame an image/parser/rendering subsystem from this
ownership probe. The separate narrow status-bar layout defect stays under #6.

## Integration and remaining gates

Require same-source complete ordinary CI, the corrected scoped regression and
normal public focus, all current required checks, review/merge-tree agreement
and expected-head merge. Update #17/#5 only for exact observed units and audit
every open issue after each update. Preserve the held Preview first failures;
any later intake/fresh qualification needs its own actual evidence. Protected
owner/native/artifact, complete critical matrix and all original issue criteria
remain open until their own contracts pass.

## First counterexample command selected zero tests

Sourced3d50990/run42331532934 compiles the explicit extra regression, then the
method-only selector without Swift Testing's full method identity selects zero
tests. Xcode returns0, but actual summary is total0/passed0/failed0/unknown;
owned outcome is normal0/25.7271s. The strict counterexample verdict correctly
rejects it. No intended assertion or ownership proof occurred; do not call the
green xcodebuild a test pass. Preserve all canonical/executed hashes, the raw
zero-case result and full original log. No product code changes are permitted
from this zero-case outcome.

Use the bounded existing PlaceholderWindowCleanupTests suite selector instead
of the unsupported method-only identifier. That suite has exactly the two
existing checks plus the one added unchanged unmarked-window regression.
Require total3, passed2, failed1, zero skips/expected failures, normal65, and
the ONE failure must identify the added method and actual classifier assertion.
This adds the existing protection checks, not a waiver or removal. The current
correction remains before actual production code. After the planned marker
attachment test is added, the corrected suite must pass all four. The private
regression body, host/source guards, wrapper and original deadlines stay intact.
This expressly revises the single-method selection assumption while preserving
the exact primary before/after assertion.

## Genuine counterexample and current integration baseline

Source1382581d/run42333220505 now genuinely executes the three-case suite:
2passes/1failure/0skip/0expected, normal owned65/44.065595s. The one failure is
exactly unmarkedWindowsAreNotStartupPlaceholders calling the actual classifier,
which returns true for the ordinary unmarked window. All1,597 canonical inputs,
one explicit executed-source addition,24pins, actual xctestrun digests, complete
raw result/logs and unchanged e901 product tree are independently verified.
Preserve both the original zero-case outcome and this genuine counterexample.

PR121 has since qualified and merged as actual main
0426e88ac81efc9347011ba6b53fb1b6d2b75f35; its product tree is unchanged from e901.
Intake this exact main before the production correction and final qualification.
The original named focus case genuinely passes at its own source; it is not
protected-owner or whole critical acceptance. Implement the previously specified
role marker only now. Add the unchanged regression to the canonical target;
verify four ownership cases, complete ordinary CI, actual normal public focus
and normal public CLI (startup behavior changes). Require all current source,
synthetic and computed merge trees to agree before expected-head integration.
No other production behavior, close site or100ms delay may change.

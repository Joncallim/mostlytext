# Require the current native Copy action to own its HTML result

## Owner outcome and live baseline

Main324155cc9cfb45116d32a2a05c2f0d392507ecea contains the integrated CLI and
private Quick Look capability evidence. PR146 remains draft at failed original
ed5a9409dcfbe62263dda0dd8157d8ea4f827e7f. Its complete14 first workflows are
retained before this correction:13 pass, including all38 original UI journeys;
Release/revision fails its original admitted-image copy assertion. A separate
passive renderer observer459a17b0 passes the unchanged56 initial functions and
observes five real image layouts. It does not reproduce or explain the earlier
failure and must not be merged; observation itself can affect layout/timing.

Source review proves a separate test-oracle defect: copiedHTML reads the general
clipboard without clearing it or establishing that the current Copy wrote it.
A no-write Copy can therefore return an earlier image/plain HTML. This slice
closes that false-positive path and requalifies the current candidate. It makes
no claim that stale clipboard ownership caused the historical failed image case.
The original failure remains evidence and blocks any broad release sign-off.

## Reconciled ownership, interfaces and invariants

Only the app-target mounted test helper, one new native counterexample in the
existing mounted suite, and its exact-count verification change. No production,
package, dependency/pin, authority, parser, renderer, language or identity change.
All original assertions,5second deadlines, six configuration/lifecycle pairs,
selection publication controls, mutations/restorations and original38 UI source/
manifest/batches remain. Import actual main before this architecture; no passive
renderer modifier or diagnostic-only workflow may enter this candidate.

On MainActor, freshNativeCopiedHTML(from: NSView) performs one native attempt:
clear the general clipboard; capture its resulting changeCount; invoke actual
selectAll and copy selectors; require a strictly newer changeCount and HTML.
The existing asynchronous copiedHTML loop calls this attempt, retaining its
original deadline,20ms yielding, diagnostics and error. Pasteboard content from
another attempt must never establish success. Diagnostic-only copy reads remain
labelled diagnostics and cannot satisfy acceptance.

## Deterministic real-native counterexample

Add one function to the existing serialized SecuredMarkdownMountedTests suite,
using the actual pinned Textual.NSTextInteractionView/TextSelectionModel, a real
harness-owned NSWindow and the actual general pasteboard. Restore its original
content and stop/close the window on every path. No mock selectors or replaced
renderer/model implementation. A one-shot selectionDidChange callback clears
the actual selection during selectAll, making real native Copy take its existing
no-selection/no-write return. Seed an owned PNG HTML canary. Replay the exact
old three-line copy attempt and require that it wrongly accepts the stale canary;
require the corrected attempt refuses this same no-write control. Remove the
callback and require a genuine actual native Copy advances ownership and yields
fresh HTML different from the canary. Log all three outcomes and change counts.
The callback is cleared before changing selection to avoid recursion and is
cleared in defer to avoid retained state. This controlled interleaving qualifies
the oracle, not the product's historical image-publication root cause.

## Concurrency, failure and resource contract

All selection/pasteboard/window operations remain MainActor isolated. No sleep,
retry, cache/grant/layout write or delayed observer is added to production. A
no-write action returns nil and the existing bounded loop yields; timeout and
original image/security assertions still fail normally. No new worker or async
lifecycle. Fixture PNG and HTML are bounded existing8pixel data; one counterexample
adds no responsiveness claim. No user strings or accessibility behaviour changes.
Copy/export interoperation remains the actual selected Textual HTML, with an
extra ownership precondition. Local product/native/engine execution remains held.

## Slices and evidence gates

1. Commit this decision and original complete-first evidence before code.
2. Implement the one-attempt helper and real native counterexample in the
   existing suite. Exact initial counts become Release57/18suites, Debug56/17;
   mutation/selection counts and all original assertions stay unchanged. Verify
   source preservation, AST, strict lint/format, pure guard/compiled-input controls
   and compliance locally only; package/native execution occurs on guarded GHA.
3. Freeze one candidate and obtain fresh complete CI/four builds, all six Preview
   pairs and unchanged required theme/PDF/math/heading/model/UI/public controls.
   Preserve every complete first workflow/logZIP/artifact/raw result before any
   correction. Native proof must show all three actual counterexample outcomes
   and every original case, exact sources/pins/compiled roles and normal owned
   lifecycle. A failure remains a failure; no unchanged retry/waiver/budget change.
4. Perform scoped orthogonal self-review, reconcile PR146/#13/#5/#8/#17 honestly,
   merge only demonstrated ready source, verify actual parents/tree and refresh
   all original issue criteria after each update. No whole issue closes from a
   private scoped pass. An unexplained historical critical intermittency remains
   explicit release debt under RELEASE_HARDENING section12. Daybreak, separate
   account, installed/signed exact RC, repeated final suites and owner acceptance
   are not established here. If real SDK interfaces differ, stop this slice and
   record a revised decision before implementation.

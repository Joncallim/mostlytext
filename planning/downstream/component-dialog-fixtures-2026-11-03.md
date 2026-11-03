# Dialog-free component test fixtures

## Owner outcome

Component tests must finish without requiring anyone to answer a native dialog.
Keep the close/recovery and filename/content-type assertions, strengthen their
observable policy checks, and leave actual sheets/save panels to native acceptance.
No production dialog behavior or timeout is changed.

## Baseline and evidence

Live master is 87d8d48b. Combined candidate 27e757cd passes all 3,317 package tests
(two existing known issues), Debug/Release app/mostlytext builds and test-target
compilation in hosted run 41536038946. That run reaches only a partial app suite
before the workflow timeout. CloseAfterRetireTests.textTypedAfterTheRetireKeepsTheWindowOpen
passes after 807.319 seconds; its fixture invokes a genuine dirty-close sheet on
a hidden test window. The run then reaches the filename test's real NSSavePanel
construction before cancellation. Do not call the last test the root cause or
claim the whole app suite passed. A separate bounded phase/sample diagnostic
preserves the unchanged close fixture; it is not product integration or full CI.

## Narrow test/adapter contract

The close-policy fixture installs an NSWindowDelegate probe for the re-request
case. It records the genuine performClose call and refuses closure, without
presenting an unanswered sheet. Keep assertions that the coordinator/window and
new text survive; also require exactly one renewed close request and a new
recovery lifetime. The real production delegate and native UI cases are unchanged.

The filename adapter requires only nameFieldStringValue and allowedContentTypes.
Introduce an internal MainActor protocol for those two properties, conform the
existing NSSavePanel and keep production callers passing that real panel. Test a
small independent field object initialized with AppKit's default name/type;
assert both the chosen filename and enforced content type through every format
transition. Do not bypass the production initialize/apply methods or duplicate
their string policy in the fake. No new module or user-visible behavior is added.

## Verification and limits

Compile all app/test targets locally without product/UI execution; run pinned
format/strict lint and Compliance. Require complete hosted package/app/build
validation after combining the change. Keep every original test case and all
existing ceilings; no skip, test filter or known-issue wrapper is added to full
CI. Focused diagnostic selection is labeled separately and never stands in for
the complete suite. Actual native sheet/save/cancel/focus acceptance and the
long-session WebKit issue remain open in #88/#118/#155.

## Bounded diagnostic result and complete alert-adapter scope

Baseline diagnostic41545356070 reaches before-renew and after-renew-before-performClose,
then hits its150-second bound without the after-performClose marker. Owned-process
samples2/3 show WindowController.windowShouldClose -> presentDirtyCloseSheet ->
makeDirtyCloseAlert -> NSAlert.init -> system-image/IconServices initialization ->
a synchronous XPC reply wait. Recovery renewal is not the observed stall. The
first sample separately records full SwiftUI window construction/layout cost.
This is a real bounded reproduction of the native initialization dependency,
not a complete app-suite pass or proof of every long-session WebKit failure.

Apply the same component boundary to the two other explicit NSAlert constructors:
close-prompt copy/configuration and export-alert cancellation. Internal MainActor
field/window protocols conform the real NSAlert; independent fixtures exercise
the same production configuration/session methods without allocating a native
alert. Preserve every existing assertion and add full button/style/message and
one-shot cancellation checks. Production continues allocating and presenting its
real alert, and actual UI acceptance remains open. No timeout or test selection
is relaxed. Full hosted validation is repeated for the new combined source.

## Termination-policy presentation recorder

Bounded full-app diagnostic 41557212648 reaches 143 passing tests without an
assertion failure before its 600.17-second bound. All four component-host
presentation controls, deleted-document discard and real D2 rendering pass.
Fourteen samples then show the termination recovery policy case calling
handleTerminationSessionResult -> presentTerminationRecoveryRequired ->
NSAlert.init -> IconServices. Its assertions inspect refusal/state/recovery,
not a user's interaction with that native sheet.

Add an optional MainActor termination-alert presenter next to the coordinator's
existing test callbacks. Keep it nil in production/native UI. Set recovery state
and choose the exact target window first; only then invoke the supplied recorder
or continue the unchanged real NSAlert path. The fixture records exactly one
presentation request and asserts both window and document-controller identity,
plus no attached sheet. Preserve every refusal, recovery-state and restored-text
assertion. The no-window policy case continues returning before presentation.
No global alert suppression, automatic response, test skip or timing change is
introduced. All 600 app cases remain required in full combined qualification.

The independent export-alert window is also Swift-owned rather than owned by
an NSWindowController. Disable its AppKit release-on-close flag, preserving its
explicit close and ARC lifetime; do not apply this fixture setting globally.

## Retired-lifetime component fixture

Diagnostic 41561585900 reproduces the same unanswered NSAlert initialization in
WindowCloseRetiredLifetimeTests after recovery renewal. Apply the existing
NSWindowDelegate request recorder to this component case too. Retain the real
performClose, assert exactly one request/new lifetime/no attached sheet, restore
the production delegate before cleanup, and preserve all persistence, session
and relaunched-text assertions. Actual dirty sheet acceptance stays native.

The static audit of every app-test closeAfterRetire caller also finds the same
implicit real dirty-sheet path in WindowControllerEpochCloseTests. Apply the
same request recorder before full execution, keep the original recovery-leak
assertion, and strengthen it with one request, retained exact live epoch and an
open window/no attached sheet. All direct close callers are now accounted for.

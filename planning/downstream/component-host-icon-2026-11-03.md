# Own component-host icon and document-proxy fields

## Owner outcome

Keep app-target component tests independent of the hosted machine's icon
service while retaining real windows, native tab ordering and all assertions.
Ordinary launches and the separate native UI-test application retain the real
product icon/proxy and still require genuine icon/Finder/appearance acceptance.

## Evidence and baseline

Master is 87d8d48b; the reviewed baseline is a84924bb. Bounded full-app diagnostic
41549331310 retains all 596 app cases and times out after 600.26 seconds. The
typed-after-retire control now passes in 0.629 seconds, confirming that #585
removed that test's former alert-initialization wait. CloseSheetContext also
passes. The next wait occurs during the stale-origin command-palette cases.

Fourteen owned-process samples show a scheduled session save calling
sessionSnapshot -> inTabOrder -> NSWindow.tabGroup -> native tab image ->
NSApplication application icon -> IconServices synchronous XPC. Later samples
show icon generation waiting on the same service. The diagnostic is a failure,
not a complete app pass or a diagnosis of the separate long-session WebKit bug.

## Binding test-host amendment

After AppDelegate's existing single-host guard and superclass initialization,
before constructing models, install one small owned bitmap only when Xcode is
hosting component tests and the launch is not -UITesting. Use the existing
XCTestConfigurationFilePath detection; add no environment override or public
option. The bitmap contains concrete local pixels and no named/system/file icon
lookup. Native tab/session code and actual product icon/resource code do not
change. No deadline, test selection, fixture source state or assertion is removed.

Three app-target controls verify the bitmap, refusal for ordinary/native UI
launch combinations, and the actual component host's installed bitmap. Compile
locally only, then execute all app cases on the hosted runner with retained
samples/results. Full combined package/app/build/lock/lint qualification remains
required before merge. Do not infer native branding, Release performance or
signed-artifact acceptance from the fixture icon.

## Second bounded result: document proxy and image readback

Diagnostic 41552942731 (c3c06 source plus diagnostic markers only) reaches real
D2 Export/Preview rendering, then times out at 600.48 seconds with fourteen
samples. The stale-origin palette cases now finish. The main thread instead
waits in WindowController.updateTitleAndEditedState -> representedURL -> native
document proxy button -> default document icon -> IconServices. A ShareKit
worker owns the service initialization. This is not a WebKit rendering stall.

The actual host bitmap control also exposes an incorrect fixture assumption:
NSApplication normalizes the image to NSCGImageSnapshotRep. Verify its rendered
CGImage dimensions and distinctive opaque black/white pixels instead of
requiring one storage representation subclass. Keep the original assertion
failure and all samples.

Expand the same explicit component presentation boundary to DocumentWindow's
documentRepresentedURL field. A window captures the existing Xcode-component-host and
not-native-UI predicate once. In that mode only, retain/read/count the proxy URL
as an owned field without allocating the system proxy widget; normal/native UI
launches forward the getter/setter to NSWindow.representedURL unchanged. The
native getter is not overridden: it stays nil in component mode so native tab
code cannot accidentally request the fixture URL's file icon. The controller
updates this explicit presentation field; its non-DocumentWindow fallback keeps
the original NSWindow assignment. Do not change window
title, edited state, native tabs, coordinator/model behavior or source URL.
This fixture is not native proxy-icon/drag-menu/Finder acceptance. Add real
component field set/clear checks and an original deleted-document controller
URL assertion; keep all prior cases and native UI launch exclusions. Full
combined qualification must execute all 600 app cases / 122 suites.

## Standalone window ownership correction

ARM full run 41557168954 passes all 3,320 package tests, builds and compilation,
then crashes at componentDocumentProxyRetainsAndClearsItsValue. The new fixture
owns a bare DocumentWindow with Swift ARC and closes it without disabling
release-on-close. [Apple's NSWindow contract](https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed)
requires ARC clients to disable that setting for standalone owned windows;
controller-owned windows use the controller's existing lifetime instead.
Set the fixture flag false, assert that precondition and keep the actual close.
Retain the crash and incomplete/restarted test logs; the later 262-case restart
is not a complete 600-case pass or evidence that the crash can be ignored.

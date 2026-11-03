# Own the component test host's application icon

## Owner outcome

Keep app-target component tests independent of the hosted machine's icon
service while retaining real windows, native tab ordering and all assertions.
Ordinary launches and the separate native UI-test application retain the real
product icon and still require genuine icon/Finder/appearance acceptance.

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

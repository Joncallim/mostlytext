# Open the existing license window from Help

Baseline main d944c3decaf34cf77fe3b48a8ad5fbcbeb67dae7. The original LC-08
contract in MostlyText #14 requires About and Help entry points. Current source
has About and application-menu buttons, but no Help-menu command. This narrow
engineering fix restores that requirement using the existing shared licenses
scene and existing localized title, without introducing another window type,
text corpus, resource source or string key.

AboutCommands owns both menu groups and reuses its existing openWindow action.
Add a CommandGroup after the standard Help placement; no change to startup
readiness admission, storage, lifecycle, rendering, native hold or product data.
The action is available under the same normal-launch command admission as the
existing About/application menu. No network access, fallback or new dependency.

Change only AboutCommands.swift and current documentation/acceptance. Validate
existing license component controls through complete hosted app/package CI,
locked compile-only local Release build and source/notice checks. No synthetic
source-string test substitutes for menu behavior. The real protected-account
Release journey must still verify every entry point, shared-window reuse,
keyboard/find/copy/VoiceOver/localized layout and exact signed resources before
LC-08 or #14 closes. Do not claim native menu acceptance from compilation alone.

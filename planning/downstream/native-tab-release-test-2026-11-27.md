# Native tab close and restore test on the private Release checkpoint

## Owner summary

The protected Release checkpoint can run the native tab tests, but one close-and-restore case tried to use a Debug menu command to make a document dirty. Release builds deliberately omit that menu. The test now edits the selected document through the normal editor before checking the dirty-close prompt and session restore. This changes the test journey, not the app's shipping commands.

## Baseline and first result

- Source: clean `main` `026c2b2e9faef1e22e622181ba10112995f82a3e` in owner-prepared stage `/Applications/MostlyTextEditorCheckpoint-026c2b2e9fae`.
- The first protected attempt passed 21 selected app tests but the UI runner timed out while enabling automation mode. Its first log, result bundle and failure receipt remain under `~/Library/Logs/MostlyTextEditorCheckpoint/026c2b2e9faef1e22e622181ba10112995f82a3e/2a833b9f01d44a6fa086fa464a433c1e/`.
- A separate same-stage diagnostic retry passed 11 UI cases and 21 app cases. `TabLifecycleUITests.testOpenFilesDirtyClosePromptAndRestore` failed at line 73 when it tried to click the absent Debug menu. That retry's log, result bundle and failure receipt remain under the sibling `85d3d8630afb4ed1befe807997c97854/` directory. Issue #5 records exact hashes and failure text.

## Test change and limits

After selecting b.md through the app's Window menu, the case checks that the visible editor contains b.md, types a local edit, and confirms it appeared. It retains the dirty-close alert, cancellation, termination, saved session and restored-tab assertions. The test uses the same editor interaction already exercised by the external-file UI cases. The Debug menu remains absent from ordinary Release.

This source change requires a new exact-merge-SHA owner stage. Build and hosted checks cannot substitute for the protected UI rerun. A passing scoped rerun will still leave manual external-file journeys, formal signing, rights/source offers, and publication as separate gates.

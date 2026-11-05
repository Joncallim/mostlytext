# Exact source observation — 5 November 2026

The original DocumentEditorSplitView observes a Swift String directly. The actual
canonical comparison treats the three byte-distinct Unicode pairs in the tests
as equal, including a pair with identical UTF-8 and UTF-16 lengths. That is the
observed comparison counterexample; this packet does not claim a mounted-app
publication result or source persistence loss.

The replacement immutable source value observes exact UTF-8 content without a
hash, normalization or byte-array allocation at view construction. Its captured
text reaches the existing unchanged Markdown/JSON format gates and callbacks.
The model already retains these authored edits through FileDocument.edited;
EditorView's own synchronization also already compares exact text.

The exact standalone production helper and actual four app test functions run
in an isolated MacDown2-named SwiftPM module. No import changes, stubs, SwiftUI,
AppKit, renderer, product, CLI, owner document or signing execution occurs. All
four functions pass Debug and Release. Source-file hashes, original observer and
raw logs retain evidence. Copy only the two hashed files to their fixture paths,
with fixture-Package.swift as Package.swift, then run swift test / swift test -c
release. Actual app compilation and whole-path publication remain hosted/native
qualification; this value unit alone closes no owning issue criterion.

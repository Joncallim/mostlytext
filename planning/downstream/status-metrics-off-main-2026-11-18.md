# Status metrics on large editor documents — 18 November 2026

## Observed source path

At main `ecec0e35380260a0076d108fdc2a7890e02b5298`, `DocumentEditorSplitView.editorPane` called `EditorTextSystem.documentMetrics()` while building the status bar. The cache avoided a rescan for selection-only renders, but every new content revision synchronously computed `String.count`, Foundation `.byWords` enumeration and line-ending counts on the main actor. This is the #17 F16 residual and a concrete possible contributor to #18's input-to-paint overrun. It is not a measured cause of the complete #18 failure.

An exploratory optimized Swift benchmark used the same three loops over a 1,078,188-byte / 1,076,195-UTF-16-unit corpus assembled once from 113 distinct repository Markdown files. The path list, corpus generator and driver are retained in `planning/downstream/evidence/status-metrics-off-main-2026-11-18/`. Corpus SHA-256: `9238355f81cf073a42465d88c912c0cf99345ccd55dd383622d81d68477e4b86`. Twelve warm samples gave median/max milliseconds: character count 1.225/1.279, word count 33.539/53.674, line endings 1.567/1.581. The driver SHA-256 is `fa8d0ea6a67d4f2b138d66743999df29553e0f049c3118cf871e5d002ce26251`. Reproduction uses `python3 make-corpus.py <repo> <corpus-path>` and `swiftc -O benchmark.swift -o <driver>` followed by `<driver> <corpus-path>`. These are isolated component timings, not mounted app paint evidence or a pass against #18's 50 ms target.

## Repair and limits

The editor now snapshots text only for a new content revision and schedules metric computation off the main actor. The status bar observes the result for its exact revision; it shows a pending count and no line-ending control until that revision settles. A newer edit cancels prior work, lets Foundation's word enumerator stop at its next 256-word cancellation check, and rejects any late result. Selection-only requests neither copy the source nor start a new scan. Authored text, selection, undo and the highlighter are unchanged.

Focused pure store tests cover same-revision reuse and old-result/new-result inversion without timed sleeps. The existing mounted metric tests await the revision result. The first cancellation implementation's two compile diagnostics and their corrections are retained in the evidence directory.

Local Xcode 26.6 results on this worktree: `swift test --filter EditorDocumentMetrics` passes eight tests/one suite in Debug; `swift test -c release --filter EditorDocumentMetrics` passes the same eight in optimized Release. A locked, unsigned Debug app build passes without launch. SwiftFormat lint, strict SwiftLint on changed Swift files, `git diff --check`, ordinary compliance and all 355 compliance tests pass. Strict release compliance remains at ten #14 provenance/source failures; no predicate was changed.

The complete hosted suites and actual Release event-to-paint measurements remain required before wider #17/#18 acceptance. The deferred protected native checkpoint remains deferred.

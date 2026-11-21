# Replace in Folder publication stays inside the selected folder

## Owner summary

Replace in Folder could rewrite a reviewed file after another process moved its parent outside the selected folder and inserted a link at the old path. The replacement still matched the reviewed file's revision, so the content guard alone did not protect the folder boundary. This change retains the chosen folder as an open directory and makes the final replacement relative to it. A changed child path now fails without writing outside the chosen folder. The existing preview, revision and encoding checks remain in place.

This is a scoped source repair for MostlyText #17 F14. Finder Trash, the complete F14 matrix, installed-app interactions and the full #17 closure criteria remain open. The owner-deferred native checkpoint is not inferred from these tests.

## Baseline and authority

- Baseline `main`: `64fd7e71e19b0f61cc0c871a0bb1b17a31e6abc0` (21 November 2026).
- The selected folder is captured by `FolderSearchModel.setRoot` before a replace review. The replacement actor retains that same authority through each file's write.
- `FileCore` owns the retained directory descriptor and root-relative publication. `TextSearch` passes it to the existing `FileStore`; the app model owns its lifetime. No new dependency is bundled and the document's authored bytes are not normalized.
- A path must be beneath the selected root by whole path components. `openat` reads existing destination metadata without following any ancestor link. The private stage is created in the selected root, and `renameatx_np` exchanges it with the destination through the retained root descriptor using `RENAME_NOFOLLOW_ANY`. The displaced revision is still checked before acceptance or rollback.
- A volume without a supported safe exchange refuses a rooted replacement. This keeps the original file and reports a failed replacement rather than using a path-based fallback across the root boundary.

## Controlled regression and limits

The test-only baseline `c9ab0328` drives the production `WorkspaceReplaceEngine` after preview, moves the reviewed file's parent outside the selected root, and replaces the old parent with a symlink. Unchanged source reported `.replaced` and changed the outside file. Its retained first-failure log is `CORTANA-Builds/mostlytext-rooted-folder-replace-failing-before-20261121.log` on Fast SSD, SHA-256 `6e35a05ee478735e278c25ae1843bf1cb1894aaf0b31b15595574779ea3f2c06`.

With the repair, the same regression passes, along with a direct final-publication interleaving and ordinary in-root replacement. Final-source focused Debug package tests pass 43 tests in seven suites (log SHA-256 `ffc01d66b20311a9aafccb95a14ce4edc3a250ada28856dbf7e3744f10e639e6`); the optimized Release selection passes 14 tests in two suites (`21c69eb3f38aa901d8e7bc3a4b86bacf09c4d87a874f4d4ea6fa5172d3d65418`). SwiftFormat lint reports zero changes and strict SwiftLint passes. A locked Debug app and test bundle build succeeded before the one-line path-conversion warning cleanup (log SHA-256 `5722ddce012e19989fedcd26bf61b07d11d12d709898669a7ac896e496f13589`); the final-source app build is left to hosted CI. The attempted local app-target test command was interrupted because it launched a test host in the owner account; no local app-test result is claimed. App-target execution is left to hosted CI, with its result recorded in the PR and issue comment after the final run.

An earlier broader concurrent local selection passed 432 of 433 tests; `RegexCancellationTests.aCancelledPathologicalRegexStopsPromptlyAndReportsCancellation` returned `.timedOut` instead of `.cancelled`. The first result is retained at `CORTANA-Builds/mostlytext-rooted-folder-replace-selected-debug-20261121.log`, SHA-256 `b7819f81dfaeee6bcd68d77a24408c1baf51abde1eb9292d5250b13e8151ddb7`. A focused replay passed four of four. That does not establish the first failure's cause. The final selected/serial CI result is reported separately, and the F08 timing gate is not waived.

Rooted replacement is intentionally limited to an existing reviewed file with a revision; it is not a general new-file publication API. These tests do not establish Finder Trash safety, installed filesystem behavior, or a final signed candidate.

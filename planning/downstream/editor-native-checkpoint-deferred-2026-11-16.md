# Editor and external-file native checkpoint — deferred 16 November 2026

## Owner summary

The owner has deferred this checkpoint until an explicit later resumption. No
desktop switch, unlock or app launch is requested now. The single entry point
`MacDown2/scripts/native-editor-checkpoint.py` prepares a clean, exact-commit
Release test build, stages its test products and source/fixture hashes in an
owner-controlled read-only location, and later refuses execution unless the
disposable test account is the active unlocked desktop. It retains the first
test log and result bundle. The build is a local unsigned test product, not a
signed/notarized V1 candidate.

## Entry point and identity

From the owner checkout, `python3 MacDown2/scripts/native-editor-checkpoint.py
plan --sha <full-final-commit>` is read-only. On resumption only, `prepare
--sha <full-final-commit>` runs ordinary compliance, formatting, linting,
XcodeGen, the locked-package check and an optimized Release build for testing.
It refuses a dirty or different source checkout, records the exact hashes of
the external-file and editor UI test sources, copies the complete test products
to `/Applications/MostlyTextEditorCheckpoint-<first-12-source-digits>`, verifies
the copy, writes `binding.json`, and removes its temporary build directory. It
prints `STAGED_NO_LAUNCH`. It never starts the app in this phase.

When the test desktop is later active, run the *same staged script* as UID 502:
`python3 /Applications/MostlyTextEditorCheckpoint-<first-12-source-digits>/checkpoint.py
accept --sha <full-final-commit>`. It checks the console, unlocked session,
owner-home denial, stage ownership, product hashes and fixture binding before
running the selected app and UI suites. Its unique receipt directory is under
the test account's `~/Library/Logs/MostlyTextEditorCheckpoint/<commit>/`.
Failed runs remain there for review; a repeat creates a separate directory.
No source or owner-home path is used by the test account's test command.

The final commit cannot be filled in until the integrated PR is frozen or
merged. The entry point requires the full 40-character value and records the
test products and exact fixture hashes at preparation. Existing #18 first
timing failures and the unresolved #19 trigger remain separate evidence; this
checkpoint does not overwrite their receipts.

## What the later run can and cannot resolve

The selected suites cover editing, composition, tab/close behavior,
external-file conflict and file-controller regressions in one pinned product.
The deferred manual matrix must observe text, disk bytes, selection/scroll,
save/close outcomes, and conflict state for clean in-place and atomic changes,
dirty conflicts, Keep Mine and Use Disk, deletion, moves, formatter storms,
debounce/close, and failed/unstable resolution. A whole-process idle-wakeup
and multi-window descriptor/task trace with a positive external-change control
is still needed for #12. For #18, a real Release input-to-visible-paint timing
run must include the first edit and all specified positions/IME/undo/viewport
cases; the prior over-50-ms first failures stay failures. For #19, only a new
historical-trigger lead justifies a fresh mounted replay; a clean retry does
not prove root cause. None of these is silently marked accepted by a green
automated suite.

The exact signed/notarized V1 candidate remains a separate release gate. The
Apple agreement and issue #14 rights/source decisions are outside this
checkpoint. Do not treat this unsigned local stage as a formal candidate.

## Consolidated owner actions when explicitly resumed

1. Sign in to and unlock the disposable `mostlytexttest` desktop, leaving it
   active for the protected run. No credential is needed in chat.
2. Observe the specified interaction, paint and whole-process idle cases on
   the pinned product, with Codex collecting the receipts and reporting actual
   failures. Only genuinely visual or manual judgments need owner input.

Codex can prepare the pinned build, fixture manifest, automated suites and
receipt paths after resumption; no further owner action is requested for them.

# Issue #119 partial acceptance checkpoint, 2026-10-29

All six existing external-change UI tests executed and passed in an optimized Release acceptance variant on CORTANA. A new deterministic regression also reproduced and fixed cancellation retaining the context callback. Serial 1/10 MiB FileCore measurements completed with raw records. **#119 and #115 remain open:** this is not the complete native behavior/performance/lifecycle matrix or a shipping-signed acceptance claim.

Source baseline: `6a915a08a81adb63bbecbdbb75c612f9d4574f9c` (existing #541 branch). Measured production-source change: only `contextCallback = nil` in DocumentFileMonitor.cancel, saved as performance/filecore-source.patch. UI setup additionally opts into the existing ISSUE117_NATIVE_ACCEPTANCE startup guard and creates a private CFFIXED_USER_HOME per test. No UI assertions were replaced, no new UI scenarios duplicate the six cases, and no app startup/security policy changed. Generated project/lockfiles are unchanged. Subsequent test-only style refactoring preserved assertions and passed the focused regression again.

## Executed results

| Evidence | Result | Retained record |
|---|---|---|
| Real ExternalFileChangesUITests, Release arm64 | 6/6, no failures, 147.659 s | logs/external-ui-release.log; logs/ui-result-summary-host.json |
| Cancellation reproduction before fix | context capture remains retained; one expected regression failure | logs/callback-lifetime-before.log |
| Monitor/probe tests after fix | 31 tests / nine suites passed, 3.951 s | logs/monitor-probe-after.log |
| Full package, serial locked dependencies | 2812 tests / 384 suites passed, 261.138 s, two known Neon issues | logs/package-summary.txt; full local log below |
| Callback regression after style cleanup | 1/1 passed, 0.001 s | logs/callback-lifetime-final.log |
| Strict SwiftLint / SwiftFormat, all MacDown2 | passed | logs/lint-full.log; logs/format-full.log |
| Source compliance inventory | passed | logs/compliance-source.log |
| Optimized serial component matrix | 126 processes, 426 validated calls; all exit zero | performance/README.md, raw.jsonl, run-manifest.json |

The known package issues are NeonReplacementEditTests.typingThenDeletingABlockInOneTurnMatchesAFreshHighlighter and replacingASelectionContainingInlineRangesMatchesAFreshHighlighter; they remain reported, not removed or suppressed by this change.

## Genuine UI scenarios

| Existing test | Result / seconds |
|---|---:|
| CancelThenUseDiskRevalidatesAgainstTheLatestDiskVersion | passed / 33.546 |
| CleanExternalReplacementReloadsWithoutAConflictSheet | passed / 5.219 |
| ConflictCloseUseDiskClosesWithoutDiscardingTheExternalVersion | passed / 25.992 |
| DirtyExternalReplacementKeepsLocalTextUntilDiskVersionIsChosen | passed / 30.162 |
| KeepMyChangesDismissesConflictAndPreservesEditorText | passed / 25.889 |
| UseDiskResolutionShowsUnavailableStateWhenBackingFileVanishes | passed / 26.851 |

These drive real app launch, owned files, editor actions, banners and the native conflict-close alert. They prove their existing assertions, not every row of issue-119-handoff.md. Session/defaults/recovery locations were isolated. The real user's session hash, recovery directory entry count/mtime and window-frame-default hash matched before/after. No real document or security setting was changed, and no authorization prompt was observed. DevToolsSecurity remained disabled; that setting alone cannot explain historical runner failures.

## Build and execution boundaries

The ordinary Release all-target test build cannot compile unrelated DEBUG-only app-unit fixtures. Retain those failed attempts; do not disable or change those tests. A disposable XcodeGen spec removes only MacDown2Tests from the scheme's test graph, leaving the existing app and MacDown2UITests sources. Its uniquely named Issue119ExternalUI scheme prevents collision with the CLI scheme on a case-insensitive filesystem. No generated project was hand-edited. A stale unsigned MacDown2Tests plugin from the failed attempt was moved out of the generated app and retained, then the same UI-only build signed successfully. Both generated app and runner verified. Signing is ad-hoc, not Developer ID or notarization proof.

Build flags: Release, arm64, `-O -whole-module-optimization`, `ENABLE_TESTABILITY=YES`, `CLANG_ENABLE_CODE_COVERAGE=NO`, `OTHER_SWIFT_FLAGS=$(inherited) -DISSUE117_NATIVE_ACCEPTANCE`; locked package versions, automatic resolution disabled, jobs two. Use XcodeGen with original MacDown2 project root, absolute canonical MacDownKit/Info.plist paths, a disposable project output and copied exact Package.resolved. The original spec, derived project, compiler/sign logs and xctestrun are retained locally.

Executed `xcodebuild test-without-building` against Issue119ExternalUI_macosx26.5-arm64.xctestrun, destination macOS arm64, parallel testing NO, only-testing MacDown2UITests/ExternalFileChangesUITests, timeouts enabled (60 s default / 120 s maximum), private runner home. The timeout is an execution guard, not performance acceptance. Result bundle: `/tmp/mostlytext-119-acceptance-20261029/external-ui-release.xcresult`. Host xcresulttool's summary agrees with the raw runner log: six passed, zero skipped/failed/expected failures. A sandbox-only summary extraction failed; host extraction succeeded without rerunning tests.

## Retained artifacts and remaining gates

Local evidence root: `/tmp/mostlytext-119-acceptance-20261029`; full package log `package-full-after.log`, successful UI build `ui-release-build-sign-cleaned.log`, earlier build failures `ui-release-build*.log`, temporary spec `ui-only-project.yml`, isolated-state receipts `user-before.json` and `user-after-ui.json`. Derived products: `/tmp/mt119-scroll-reload-derived`. Committed artifact-checksums.json hashes the local logs and xcresult files; the large bundle and binary build products are not committed. Performance raw records contain only generated fixture metadata, digests and measurements.

See [the deterministic admission design](admission-test-design.md). Current tracking is accounting, not a queue; snapshotNow bypasses even that tracking. The one-active/one-latest-pending and shared four-worker requirements are **unimplemented/unverified here**. Cancellation now releases contextCallback; that fix must not be represented as admission completion.

Still required: the rest of the real behavior and encoding/view-state corpus, own-save/subsequent external edits, rename/cross-parent/ambiguous identity, permission/non-regular-file cases, pending close/recovery states, formatter storms and final-revision publication; native foreground/total latency, MainActor conflict/close I/O, same-parent search, idle activity and 1/10/50-window handle/memory evidence. Cold-storage measurements were not obtained. No issue closure, formal PR approval, merge or gate waiver accompanies this checkpoint.


## New navigation supersedes reload restoration — 1 November 2026

Source review found that editRevision alone did not distinguish a pending disk
reload from a later navigation action. Both delayed passes could restore the old
viewport after an outline jump, selection movement or user scroll. The correction
clears the reload snapshot and its own raw fallback at explicit navigation APIs,
keyboard/mouse input, changed native selection and user-live-scroll notifications.
Ordinary layout/bounds notifications and the unchanged replacement selection do
not revoke restoration. Unrelated session offsets and frame-height sync survive.
The live-scroll observer is removed on dismantle and ignores an older scroll view.

EditorExternalViewportIntentTests drives the restoration seam without sleeps,
before and between passes, plus selection, user-scroll and raw-offset ownership
controls. Hosted validation and independent source re-review are required on the
corrected head. The historical native evidence above remains attached to its
original source; no new native journey or #119 closure is claimed by this fix.

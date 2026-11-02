# UI test runner: "Timed out while enabling automation mode" (three failures, 2026-10-16)

**Status: diagnosed to a hypothesis; the cause is not proven and needs a person at the Mac.** No security or system setting was changed, and the same run was not retried beyond the three attempts below.

## What the logs and xcresult bundles show
| Run | Local time | Result | Evidence |
|---|---|---|---|
| Native UI suite (all 37 tests) | 07:54, on `d42f2723` | **passed**, 37/37, 319.7 s | `Test-MacDown2-2026.10.16_07-54-14-+0800.xcresult`; log shows `Setting up automation session` before each test |
| `PinyinCompositionUITests` run 1 | 12:48 | runner failed to initialize, 0 tests ran | `..._12-48-10-+0800.xcresult`; error at 12:49:20 |
| run 2 | 12:49 | same | `..._12-49-59-+0800.xcresult`; error at 12:51:07 |
| run 3 | 13:32 | same | `..._13-32-40-+0800.xcresult`; error at 13:33:47; xcresult summary: 1 failed test, "MacDown2UITests-Runner (11913) encountered an error" |

- All three failures are identical and occur before any test body runs: about 65-75 s after the runner starts, XCTest's `XCTFuture` (code 1000) gives up enabling automation mode. Same Mac, same command, same scheme as the passing run.
- The passing run happened while the owner was at the machine. The three failures happened while they were away.
- Session state at 13:3x: console user `jonathanlim` is the logged-in console session, no `CGSSessionScreenIsLocked` key in the I/O Registry, display kept awake by Amphetamine (so not a sleeping or locked display as far as readable), `loginwindow` running since 30 Sep.
- `DevToolsSecurity -status` reports "Developer mode is currently disabled". It is not known whether it was disabled during the passing run (it was not recorded then); if it was, this alone does not explain the difference.
- The unified log gave no entries for `testmanagerd`, `SecurityAgent`, `authd` or the XCTest subsystem in either window (not readable from this account), so **an unanswered authorization or privacy (TCC) prompt is a hypothesis, not an observation.** It fits: the UI runner is rebuilt and re-signed on each build, and a rebuilt runner can trigger a new Accessibility/Automation approval, or a Developer-mode authorization, that only a person can answer.

## Smallest action needed at CORTANA
1. Be at the Mac with the screen unlocked, then run (from a Terminal) the Pinyin suite command in `planning/INTEGRATION_INVENTORY_2026-10-16.md` (section "Pinyin").
2. If a dialog appears (e.g. "MacDown2UITests-Runner wants to control this computer" or a request to enable Developer Mode / enter an administrator password), approve it.
3. If no dialog appears and it times out again, open System Settings, Privacy & Security, Accessibility, and check whether `MacDown2UITests-Runner` is listed and enabled; tell me what you see. Do not change other security settings.

Nothing here authorises changing a security setting without the owner.

## Later observation (2026-10-29)

All six real ExternalFileChangesUITests completed in optimized Release on CORTANA without changing security settings or answering an authorization prompt. DevToolsSecurity still reported disabled. This does not establish the cause of the October 16 failures or prove every UI suite is now runnable. See [the exact six-case evidence](../issue-119-2026-10-29/README.md); no historical failure has been erased or relabelled as a pass.

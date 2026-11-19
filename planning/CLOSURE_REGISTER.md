# File-safety closure register

Finite register for the file-safety and release-convergence handoff of 10 October 2026. It records, per obligation, what is proved, by which immutable evidence, and what is still missing. It is not an epic and does not replace the owner issues; it must be updated in the PR that changes an obligation's status. A shared predicate, a closed issue, a test count or a similar-looking passing test is not evidence for an obligation here.

Reproducibility evidence (**final head `268bee5f`**, after the reviews' fixes #412–#470): `planning/downstream/evidence/package-serial-3x/` — three consecutive serial runs of the full package suite, nothing skipped (2494 tests each, all passed); `planning/downstream/evidence/app-target-serial-3x/` — three consecutive serial runs of `MacDown2Tests` (376 tests each, all passed); `planning/downstream/evidence/ui-native-run/` — one full native `MacDown2UITests` run, 37/37 passed (screen free, interactive session); `planning/downstream/evidence/release-performance/` — two Release-configuration runs of the performance suites (`cec1d28e` and the final head `268bee5f`), 32/32 passed each (the 50 ms Markdown budget at 1 MB remains the known #203 gap, owner disposition: restate as size-dependent).

Baseline: `master` after #470. Evidence is **CI-green PRs plus local runs** on one host (macOS 26.5.1). The consecutive-suite evidence above is for the final implementation head; any later source change invalidates it. No signed candidate, native Quick Look/WebKit corroboration or whole-app Release memory/20-tab audit has been executed (a native `MacDown2UITests` run and a Release run of the performance suites now exist; see Reproducibility evidence). Earlier stalls of the package suite (and the 41–59 timing failures of parallel runs) were traced to AppKit window-transition animations in test windows stranding dispatch workers (#155, fixed by #421) and are not part of this evidence.

## Recovery lifetime and queued Save As — 19 November 2026

The source-only, package-level active-tab gap recorded in the third review round below was reproduced. Both ordinary recovery renewal and failed-close preservation now identify the original tab before awaiting the recovery actor, then recheck that tab's document lifetime before publishing a new epoch. The parameterized switched-tab test fails four expectations against the previous source and passes both routes with the repair. It checks that the other tab stays active, the original text is retained, and the new epoch has durable recovery bytes. Eight focused close/recovery tests pass locally. This is package evidence; a real native tab-switch and failed-close journey remains pending under issue #17.

The queued Save As lineage test now covers an external file created after destination admission while the earlier encoding-changing save is held at publication. Both Latin-1 and UTF-8 BOM cases preserve the external file and the accepted source bytes. The combined destination-baseline, lineage and recovery selection ran 21 tests in three suites locally. The app's Save As panel and installed-file journey remain separate native acceptance.

## Independent reviews (2026-10-11, three Opus reviewers, none of whom wrote the code)

| Scope | Finding | Disposition |
| --- | --- | --- |
| Publication/recovery | **P1** Retry could delete the newer unsaved recovery of a document in a non-active tab | Reproduced; fixed #412 (`WorkspaceInactiveTabRetryTests`, fails on old source) |
| Publication/recovery | P2 a save completing after a tab switch was applied to no tab → false external conflict on the next save | Reproduced; fixed #414 (`WorkspaceTabSwitchSaveTests`, 4 failed expectations before) |
| Publication/recovery | P2 minor: temp-file removal failure after acceptance reports save failure | Source-confirmed only; unreproduced; open |
| Publication/recovery | Recovery ledger quarantine drops fences/redirects after a crash | Unsupported suspicion; open limitation |
| Authority | No outside-read path in the contained reader; test gaps and a runtime-enforcement check | #411 (`readStrict` tests, FIFO bound, `verifyEnforcement`) |
| Authority | P2 `realpath` hint can block on a stalled network mount and ignores cancellation | Open; resolve with `readlinkat` beneath the descriptor in #121 stage C |
| Authority | P1–P2 Preview/Export Unicode containment (NFC/NFD sibling) | **Refuted**: Foundation file URLs normalise to NFD on both sides, so the siblings are indistinguishable in URL space |
| Authority | P2 stale resource request: mutable handler context across HTML revisions (documented #121 item) | Open; #121 stages B–D |
| Authority | P2 Replace in Folder: dirty-open-file check precedes the write; old run keeps writing during a root switch | Fixed #419 (`beforeRootRebuild` seam; the root-switch test uses a sleeping Task for ordering, so it is timing-sensitive in principle) |
| Cross-feature | P1 text filter result applied without the IME guard | #413 guard added; the test does NOT discriminate headlessly, so source-confirmed only |
| Cross-feature | P2 `updateBaseline` raced the first bind's probe | Reproduced; fixed #415 (2 failed expectations before). #415 had no bound on probes started: see the post-fix review below |
| Cross-feature | P2 line-helper change (#396) pinned only on the Tab path | #417 pins Return, Smart Home, fence, front matter (4 of 7 tests fail on pre-#396 helpers); on re-review only one Return test is shown to discriminate, so the others are regression guards, not proof |
| Cross-feature | P2 Find freshness ignored query/options | Reproduced at model layer; fixed #416 |
| Cross-feature | Register/README inconsistencies | Corrected in this change |

## First native UI run and its review (2026-10-13)

| Finding | Disposition |
| --- | --- |
| First execution of `MacDown2UITests` (on `b848deaa`): 25 passed, 8 failed. Triage found 6 PRODUCT defects, the rest stale tests, none environmental | Fixed #468; full target 33/33 afterwards (`evidence/ui-native-run/`) |
| **Regression from #448 (mine):** the editor mounts while `WindowController.init` builds the window, then `makeSessionsForActiveTab` marked it 'awaiting EditorView', so Bold, Text Filter, snippets and Convert Line Endings were refused for the window's whole life in every ordinary window. The unit test passed only because of that bug | Fixed #468: only a system the call creates itself is marked; the test uses Preview Only and a mounted-case test was added |
| Find in Document: the bar did not appear on the first ⌃F (`EditorFindModelStore` was not observable); query focus from `onAppear` was dropped (typing went into the document); menus did not refresh after focus moved in | Fixed #468 |
| Close sheet and `resolveConflict` compared `mutationGeneration`, which background reconciles bump while a sheet is open, discarding the user's choice | Fixed #468 (identity, URL, exact text, state, revisions). **Independent review found the replacement dropped the backing-state check**: a file deleted while the 'Save changes?' sheet was up no longer re-ran the close flow (Discard discarded the last copy). Fixed in the same PR (`backingState` in the context; test fails without it) |
| First-run welcome: the container's identifier overwrote both buttons' identifiers; either choice opened a second empty Untitled tab. **Review:** the first fix made launch skip the full session restore, dropping a real saved session | Fixed #468: only the empty-session Untitled fallback is skipped; saved session still restored (3 tests) |
| Stale tests: bracket pairing in plain text is intended (EPIC-22 4a), so the test now asserts that `*`, `_`, backtick do not pair; one `isEnabled` check waits up to 2 s; a Find step matched the Help menu's search field | Fixed #468 without weakening the assertions (reviewed) |
| Debug-only launch argument `-fileMonitorDebounceMs` (needs `-UITesting`; `launchArguments` is empty in Release) | Added #468; verified from source, not by a Release build |
| ⌘F did nothing in the editor: Find in Document was ⌃F by an earlier deliberate choice and the Edit menu has no standard Find submenu | **Owner decision (2026-10-13): bind ⌘F.** Find in Document is now ⌘F (it replaces ⌃F; a hidden second ⌃F item does not register its shortcut in a SwiftUI command). `testCommandFOpensTheFindBar` (native). Find Next/Previous (⌘G/⌘⇧G) remain unbound: the bar has buttons only |

## Native IME / dead-key corroboration (2026-10-13)

`DeadKeyCompositionUITests` (3 tests, native, real synthesized key events on the ABC layout: ⌥E opens a dead-key composition, the next `e` commits `é`; no system setting changed): the commit produces `é`; the commit still works after an Undo (the #439 regression, now confirmed through the real text input system, not only `setMarkedText`); an external reload arriving while a composition is open is not reverted by the commit (the reload clears the composition, the typed `e` lands at the preserved caret inside the reloaded text, and the old text does not return — #436/#443). All pass. **Limits:** a dead-key composition exercises the same marked-text lifecycle as an input method but is not a CJK/Pinyin/Kana engine; the tests assume the ABC/US layout; one run, one host. An earlier attempt of these tests ran while the owner's screen was occupied by a full-screen game and failed for lack of a window (recorded here because it also sent keystrokes to the wrong app); UI runs now require the screen to be free.

## Thirteenth review round (2026-10-13, Opus, exact head `52107b38`)

| Finding | Disposition |
| --- | --- |
| No P0/P1. #458 held against probes for a conflict arriving during the mint, a rename during the mint, a pending move, watcher rebind with the live document's revision/encoding, queued old-lifetime recovery writes, Save As -> edit -> relaunch, conflict flows (Use Disk Version, Keep Mine, relaunch) | Sound |
| P3 (reproduced; needs a failed close retry then a retry; real-app reach believed, not shown) the #458 helpers persisted the disk-identical text of a document that turned clean during the epoch mint; nothing removes that record and a relaunch after the file changed restores it as a false conflict (Keep Mine would then overwrite the newer disk version) | Fixed #461: a clean document moves to the new lifetime without a recovery write (suite-level mutation: the record `saved text` appears with the unconditional persist). The failed-close helper shares the change; it is private and has no direct test |
| Package-level `renewRecoveryLifetime` / `preserveOpenDocumentAfterFailedCloseRetirement` persist unconditionally | Harmless in `closeAfterRetire` (the next `performClose` retires the record); unchanged |
| Independent review of the exact final head `d1d8d4e8` (narrow review of the only change since `52107b38`, #461) | No P0/P1/P2: the change is correct (edit right after the skip is recorded under the new lifetime; relaunch after a disk change restores clean text with no conflict; clean-but-unavailable is not reachable; notice/retry state and `scheduleSaveSession` unchanged). **One P3, reproduced:** the package-level `WorkspaceModel.renewRecoveryLifetime` and `preserveOpenDocumentAfterFailedCloseRetirement` (`WorkspaceModel+CloseRecovery.swift`) still persist unconditionally, so a clean document that reaches `renewRecoveryLifetime` through `closeAfterRetire` (e.g. a clean close racing an external reload) gets a stale record that a relaunch after a disk change restores as a false conflict. **Fixed #464** (owner-requested): the same `state != .clean` guard in both package helpers; the new test covers both and fails with the guard replaced by `true` |

## Twelfth review round (2026-10-13, Opus, exact head `51ac4816`)

| Finding | Disposition |
| --- | --- |
| P2 x2 (reproduced; reachable: a failed close retry then typing during the epoch mint; a Finder move while typing) the app-side `preserveOpenDocumentAfterFailedClose` and `preserveCurrentDocumentAfterStaleInitialMove` gave up when anything changed during their epoch-mint await, after the old lifetime was already retired, stranding the window on it (recovery writes rejected; session autosave failing) | Fixed #458: they require only the same document id and epoch within the controller's lifecycle and rebase the new lifetime onto the live document (`liveDocumentOnSameLifetime`). The stale-move test fails with the old helpers and passes; the failed-close-retry test passes either way in the direct-controller harness (regression guard, not shown to discriminate) |
| SwiftTreeSitter `String+Data.swift:20` 'location is greater than end' aborts Debug test hosts under rapid whole-text replacement with a window's highlighter | Not a Release issue: it is an `assertionFailure` (compiled out of Release; the function then returns nil). Trigger: Neon's background sublayer resolution reading a stale range. Avoid creating a full `WindowController` in tests that churn text. Open (dependency) |
| Pre-existing (found by H5 step 1): replacing a selection whose old text contains whole Markdown inline ranges (paste over a selected paragraph, a wide spliced edit) leaves inline highlighting in that region different from a fresh highlighter until the document is reopened; typing then deleting a block in one main-actor turn also diverges | `ts_tree_edit` collapses included ranges inside the edit to zero length; `SwiftTreeSitterLayer.encorporateRanges` keeps them, the merged list overlaps the new ranges, `ts_parser_set_included_ranges` returns false (ignored by SwiftTreeSitter) and the inline sublayer keeps its stale ranges. Release and Debug, deterministic (5/5 each). Recorded as known issues in `NeonReplacementEditTests` (flip when fixed). Open (dependency) |
| `resumePendingClose`, `completeCloseAfterRecoveryRetry`, `matchesPresentedContext` compare `mutationGeneration` | P3, fail-safe (a bump keeps the window open; the user closes again); open |

## Eleventh review round (2026-10-13, Opus, exact head `304713dd`)

| Finding | Disposition |
| --- | --- |
| P2 (reproduced; reachable in principle: a rotation must finish on the same document inside the retire) #454 dropped the `mutationGeneration` comparison and with it the implicit catch of a recovery-lifetime change: a Discard whose retire of lifetime E1 overlapped a renew/preserve/move-follow onto E2 (same text and state) closed the window without retiring E2, leaving the discarded text loadable | Fixed #456: `closeAfterRetire` also requires the same recovery epoch. #454's deterministic test had used a lifetime change as its generation-bump fixture and so pinned the wrong behaviour; rewritten (edit reverted to identical text). The real reconcile stays covered by `DeletedDocumentDiscardTests` |
| `resumePendingClose` / `completeCloseAfterRecoveryRetry` still compare `mutationGeneration` | P3, fail-safe (a bump keeps the window open on a fresh lifetime; the user closes again); open |
| Flake hunt: 40 iterations of ~20 timing-sensitive app suites and 40 full serial runs of Workspace/FileCore/EditorCore | No intermittent failure. The #454 flake was a product-side reconcile racing the retire, made visible by a fixture whose 'deleted' file still exists |

## Tenth review round (2026-10-12, Opus, exact head `45d7966f`) and the serial-run flake

| Finding | Disposition |
| --- | --- |
| P2 (source-only; power loss only) the migration destination was written without a flush while the ledger redirect recorded next is flushed (#449) and the source is deleted after it | Fixed #453 (`writeMigrationDestination` uses `DurableFileWriter`). Ordinary recovery saves stay unflushed by owner decision |
| P2 (source-only; failing disk only) `F_FULLFSYNC` failure of any kind fell back to plain `fsync`, which could report durability the device did not give | Fixed #453 (fallback only for ENOTSUP/EINVAL/ENOTTY; test) |
| Serial evidence on `9f859e9c`: app-target run 3 failed `discardingADeletedDocumentRetiresItsRecoveryAndClosesTheWindow` | Product bug, not a test artifact: `closeAfterRetire` required an unchanged `mutationGeneration`; a background reconcile bumped it (2 -> 3) with identical text and state during the retire, leaving the window open and re-prompting (no data loss). Fixed #454: close when id, state and exact text are unchanged. Reproduced about 1 in 16 under `-run-tests-until-failure`; 5 close suites x 40 iterations pass after the fix |
| Multi-window relaunch ordering of recovery epochs/fences | No dedicated test written in this round; remains PARTIAL (family D) |

## Ninth review round (2026-10-12, Opus, exact head `bb2775c1`)

| Finding | Disposition |
| --- | --- |
| P2 (reproduced; needs a failing directory flush, not seen on APFS/HFS+/MS-DOS/ExFAT images; network volumes untested) `DurableFileWriter` threw after the rename had published the ledger, so `publishFenceLedger` callers kept the old in-memory ledger while disk held the new one | Fixed #451: throws only before the rename; afterwards returns whether the directory flush succeeded |
| P2 (source-only) a failing `close(descriptor)` was followed by a second close in the catch (a descriptor number another thread may already own) | Fixed #451: the descriptor is closed exactly once on every path (not unit-testable: libc `close` is not injectable) |
| Temp files left by a crash are hidden dot-files and never deleted | Cosmetic; open |
| #448 (never-mounted editors), drag-and-drop, opening an already-open dirty document (focus only), Reopen with Encoding while dirty, HTML preview (buffer text, saved-folder base), session autosave | Reviewed; sound. No Revert command exists |

## Eighth review round (2026-10-12, Opus, exact head `54b06b3a`)

| Finding | Disposition |
| --- | --- |
| P2 (reproduced; real app: a window opened or restored in Preview Only) #446 marked a system detached only on dismantle, so the eagerly created system of a never-mounted window still accepted Text Filter / Insert Snippet / Convert Line Endings and lost the result on the next mount | Fixed #448 (`WindowController.makeSessionsForActiveTab` marks the system awaiting its view via `setAwaitingEditorView(true)`; `makeNSView` clears it) |
| CI cost of #449 | Package suite ~30 s slower locally and ~40 s on CI. One CI run of #449 failed on a very slow app test (`newFileFromAnExplicitOriginCreatesAndOpens…`, 627 s against 15–27 s elsewhere); a re-run of the same commit passed, so it is recorded as runner variance, not shown to be caused by the flush |
| P2 (reproduced; needs a corrupt recovery fence ledger) a quarantined ledger is replaced by an empty one, dropping an unacknowledged migration redirect: the unsaved text stays on disk but `load(old)` returns nil. From source: the generation floors reset too, so a retired lifetime whose file deletion had failed could load again | **Decision (owner, 2026-10-12): the cheap option.** The ledger is now written durably (`DurableFileWriter`: data `F_FULLFSYNC` before the rename, directory flush after), shrinking the corruption window. NOT done: rebuilding floors/redirects on quarantine, orphan-recovery surfacing, and `F_FULLFSYNC` for document saves (no Swift code in the package fsyncs document writes; Foundation `.atomic` only). These remain a known limitation for the 1.0 decision |
| Not covered in depth | WebKit scheme-handler reads while dirty, file drag-and-drop, opening an already-open dirty document from Recent Documents, Revert / Reopen with Encoding while dirty, autosave timers |

## Seventh review round (2026-10-12, Opus, exact head `6e146d89`)

| Finding | Disposition |
| --- | --- |
| P2 (reproduced; real app: Preview Only + Text Filter / snippet) a command edit applied while the editor pane is unmounted reached the hidden text view but never the model (no delegate), and the next mount pushed the model back: the result vanished silently | Fixed #446: `EditorTextSystem.isDetachedFromEditorView` (set on dismantle, cleared on make); `canApplyCommandEdit` refuses while detached; the Text Filter editing target and `insertSnippet` decline. The app-level gates are not directly tested; Format JSON stays enabled in the menu but is a no-op |
| #443 (publish-time model check) | Held against every attack: every writer of document text in `MacDown2/` and `Workspace` reviewed; reload/use-external/move paths set `lastExternalReplacementText`; no keystroke/undo/IME discarded except the stated trade-off |
| `ExportCoordinator`, `TextFilterCoordinator`, `WindowCoordinator+FileTree` | Reviewed; sound |
| Save As encoding lineage | New adverse-order test (encoding save held at publication, ordinary save and Save As queued behind it) passes. Package-API only, fails safe: an ordinary save queued behind a Save As reports `fileChangedDuringRead` (the app is protected by `inFlightSaveAsByDocumentID`) |

## Sixth review round (2026-10-12, Opus, exact head `c64da714`)

| Finding | Disposition |
| --- | --- |
| P2 (reproduced in an app-shaped harness; real-app reachability believed, not shown natively) a view publish (keystroke, composition commit, undo/redo) that reached `textDidChange` BEFORE SwiftUI rendered a model-only replacement still published the stale view text, because the divergence flag was only set from `updateNSView` | Fixed #443: the model is compared at publish time with the last agreed text and the text of the last external replacement; the flag was removed. Trade-off: a keystroke racing a model replacement is discarded in favour of the model |
| `preserveOpenDocumentAfterFailedCloseRetirement` check-before-persist revert (package API only) | Fixed #444 (60-offset sweep; the previous body fails it) |
| `ContentAreaView.textBinding` writes via `updateActiveDocument`; `EditorView` has no `.id(identity)` and sets `textBinding`/`system` only in `makeNSView` | Latent: harmless with one tab per window; would break if several tabs share one view |
| `replaceTextFromExternal` while marked text is open | Not a defect (it clears the marked state); optional hardening: `inputContext?.discardMarkedText()` |
| `ExportCoordinator`, `TextFilterCoordinator`, `WindowCoordinator+FileTree:296` | Not reviewed in depth in this round; covered by the next |

## Fifth review round (2026-10-12, Opus, exact head `b17bcf15`)

| Finding | Disposition |
| --- | --- |
| **P1** (real app, regression from #436) the editor's last-agreed text was not updated after undo/redo or an external replacement, so the first IME/dead-key composition afterwards was mistaken for a model replacement and its commit discarded | Reproduced; fixed #439 (`updateNSView` records agreement whenever model and view are equal outside a composition; the undo/redo publish records it). Tested with `setMarkedText`/`insertText`, not a real input method |
| P2 (real app, regression from #437) `renewRecoveryLifetime` published an older copy after its persist: keystrokes typed during the await were reverted (54/60 offsets); an edit during the epoch mint left the window on the retired lifetime (5/60) | Reproduced; fixed #440 (rebased on the live document, published before persisting; 60-offset sweep) |
| `preserveOpenDocumentAfterFailedCloseRetirement` has the same check-before-persist, unconditional-publish shape | Source-only, package API only; open |
| Save As encoding lineage (`DocumentWriter`), ExternalFileController publication sites | Reviewed; no defect found. No new adverse-order Save As lineage test was written |

## Fourth review round (2026-10-12, Opus, exact head `bcaea668`)

| Finding | Disposition |
| --- | --- |
| **P1** (real app) IME composition commit reverted a model replacement made during the composition (external reload, Use Disk Version, Replace in Folder): `updateNSView` skips the push while marked text is open and the commit published the view's stale text; the next Save then overwrote the external content with no conflict prompt | Reproduced; fixed #436 (`EditorModelSyncState`; the commit adopts the model if it diverged while a push was skipped; control test for the undisturbed composition). Tested with `setMarkedText`/`insertText`, not a real input method: native confirmation outstanding |
| P2 (real app) a window kept open after a successful close-time retire (text typed in the gap) stayed on the RETIRED recovery lifetime: recovery writes were rejected and session autosave failed for every window | Reproduced; fixed #437 (`closeAfterRetire` async; `renewRecoveryLifetime(retiredFrom:)`; mutation removing the renew call fails the test with 3 issues) |
| `WorkspaceModel.resolveClose` captures `closingTabID` after the discard retire's await | Source-only, package-only, harmless today (the second retire is a no-op); open |
| #433/#434 | Mutation-tested by the reviewer; no new route back into the #415 loop; next pending tab in a batch gets the same treatment |

## Third review round (2026-10-12, Opus, exact head `ebf6445e`)

| Finding | Disposition |
| --- | --- |
| P2 (app-reachable, needs a slow probe) #428 counted probes already retired, so while one stayed suspended every controller echo started another probe (78k probes in 300 ms) | Reproduced; fixed #433 (in-flight probes tracked per request sequence; mutation back to the total count fails the test with 72189 probes) |
| P2 (package API only) Save/Discard-and-close acted on the active tab while `TabStore.resolveClose` closes the pending tab (batch closes, or a tab switch after the request): the dirty pending tab was removed unwritten; Discard retired the active tab's recovery | Reproduced (the Discard path too); fixed #434 (`resolveClose` activates the pending tab first) |
| `preserveOpenDocumentAfterFailedCloseRetirement` gives up if the active tab changes during its await (fails safe; tab left on an ambiguous lifetime) | Source-only, package-only; open |

## Second post-fix review (2026-10-12, Opus, exact head `d2b7e242`)

| Finding | Disposition |
| --- | --- |
| P2 (app-reachable) #423 stopped identity-only updates from retiring a probe already in flight, so a pre-save probe was published as current after the save's baseline update and could revert the just-saved text | Reproduced; fixed #428 (probes counted while in flight; retire + re-probe only if one is, so the #415 loop cannot return) |
| P2 latent (package API; one tab per model in the app) Save-and-close judged success and retired recovery against the active tab, so a failed save with a tab switch closed the unsaved tab and deleted its recovery; `TabStore.resolveClose` used a pre-await index | Reproduced; fixed #429 (`WorkspaceCloseTabSwitchTests`) |
| P2 latent `reconcileSaveConflict` and its retry were active-tab-only | Reproduced; fixed #430 |
| P2 latent `prepareSaveAsRecoveryContinuation` was active-tab-only (retry stuck until the tab is activated) | Reproduced; fixed #431; one existing test's expectation changed deliberately (owner completes, active tab untouched) |
| Watcher-rebind lost update | Refuted for the ordinary path (bind sets its policy synchronously before suspending; the update task is queued after it). Residual: if the two tasks ran at different priorities; unproven, open |

## Post-fix cross-boundary review (2026-10-12, Opus, exact head `2861e1a4`)

| Finding | Disposition |
| --- | --- |
| **P1** #415 `updateBaseline` re-probed on every identity change; the app feeds it each probe result, so a conflicted dirty document probed forever (201 probes for one external change) | Reproduced; fixed #423 (`anIdentityOnlyBaselineChangeNeverProbes`, 50 identities → exactly 1 probe; fails on the #415 behaviour). Only a decoding-policy change re-probes |
| P2 Save As finishing after a tab switch was dropped (finalisation, rebind and failure surfacing consulted only the active tab) | Reproduced; fixed #424 (`aSaveAsCompletedWhileAnotherTabIsActiveRebindsItsOwnTab`) |
| P2 Find provenance stamped at search start, so a cancelled search left earlier matches current for new text | Reproduced; fixed #425 (stamped at commit). `replaceAllTransaction` still takes no live text; callers must check `matchesAreCurrent` first |
| Watcher rebind could lose an update between the captured policy and the live document | Hypothesis, unreproduced; open |

Status: **PROVED** (production-path regression at the required layer, discrimination shown), **PARTIAL** (some scenarios proved; gap named), **OPEN** (not started or no proof), **BLOCKED** (needs an environment/authority not available).

## Named regressions

| ID | Owner | Invariant | Evidence | Status | Missing |
| --- | --- | --- | --- | --- | --- |
| R1 | #183 F01 / #375 | An obsolete disk snapshot (Use Disk Version / Reopen) cannot replace newer text or another document | `UseDiskVersionRaceTests`: edit (#374 series), tab switch, recovery-lifetime change and disposal during the held cleanup (#403; guard removal fails 13 expectations) | PARTIAL | Native (AppKit tab/window) corroboration; recovery bytes after each transition are asserted indirectly (documents), not read from disk |
| R2 | #183 F01 / #376 | Recovery retry / Save As continuation cannot publish or acknowledge over a live lifetime | `WorkspaceRecoveryRetryRaceTests` (preserve path); #391/#404 `WorkspaceSaveAsContinuationRaceTests` (live edit, tab switch, recovery-lifetime change, tab close, control; recovery bytes load; guard removal fails 14 expectations) | PARTIAL | Stale cleanup *acknowledgement* after the lifetime moves is asserted only through non-publication; lifetime change and tab close are covered by #404 |
| R3 | #183 F10 / #378 | A Save As queued behind an encoding-changing save follows the accepted lineage | #392 `WorkspaceSaveAsLineageAdverseOrderTests` (Latin-1, UTF-8 BOM; held at real publication; bytes and returned metadata; inheritance removal fails 4 expectations). The 19 November extension keeps an externally created destination's bytes while Save As waits behind the held save, in both encoding cases. | PROVED (package) | Native Save As panel acceptance remains under R7; other encodings are not in scope (supported list not expanded) |
| R4 | #183 / #379 | Watcher bind retry uses the live document's policy; stale lifetimes bind nothing | #393 `ExternalFileControllerBindRetryFlowTests` (real first-watch failure, controlled sleeper, Latin-1 save during the wait, later external edit reconciles; reverting to the captured document fails with the historical symptoms) | PARTIAL | Deletion after rebind; native FSEvents timing beyond the controlled sleeper. Skipped-bind and A→B→A are covered by #405 |
| R5 | #183 / #377 | Closed/held/stale Find results cannot authorise replacement or republish | #394 `EditorFindModelHeldSearchTests`; earlier `EditorFindModelStaleMatchTests` (exact-scalar identity, IME marked text, cancel) | PARTIAL | Mounted `FindBarView` live-refresh and closed-bar publication paths; committed IME replacement through the mounted editor |
| R6 | #183 / #381, #382 | IME fail-open; bare-CR/mixed-EOL transforms; one undo transaction | #396 `EditingAssistBareCRTests` (Markdown-assist Tab, Shift-Tab, heading; 7 fail on old source); `EditorMixedSeparatorTransformTests`, `EditorCompositionBoundaryTests` | PARTIAL | App-level JSON-formatting capture/application guards (`WindowCoordinator.performJSONFormatting`: needs a mounted key-window harness; formatted-equals-snapshot check still uses canonical `!=`); Option-click/drag composition is not claimed |
| R7 | #173, #119, #120, #88 | Navigation, external-file, close and Save As UI behave as promised | `MacDown2UITests` executed natively once: 33/33 on `cec1d28e` (`evidence/ui-native-run/`) | PARTIAL | `MacDown2UITests` are built but not run in CI; needs a native UI session |

## Harness trustworthiness

| ID | Owner | Evidence | Status | Missing |
| --- | --- | --- | --- | --- |
| H1 | #159 | #385 typed readiness error + runner cancelled/awaited before teardown; #390 ESRCH-only death checks and a controlled watchdog that releases the real timeout verdict after fixture readiness (lifecycle suite 4/4 at load ≈ 22) | PARTIAL | Other load-fragile TextFilter tests (output-cap race, still-writing descendant under a 2 s bound, `fourth-pass` race) still use wall-clock bounds; a shared async fixture owner for all lifecycle tests |
| H2 | #215 | #386 never-allocatable descriptor | PROVED | — |
| H3 | #163 | #387 `GatedParseEngine`; production busy-state defect reproduced then fixed | PROVED | — |
| H4 | #155 | Stack-sampled stalls showed `Dispatch Thread Soft Limit: 64 reached` with ~65 workers in `-[NSAnimation _runBlocking]`: test windows' order-front/out transitions strand a worker each (probe: 100 windows → 69 threads, 6 with `animationBehavior = .none`). #421 sets it on all 24 test windows; the previously stalling full serial command then completed on every attempt (3/3 final-head runs). Also #406 (TextFilter `NSFileHandleOperationException`) and #420 (JSON gate deadlock hazard) | PARTIAL | App code creating windows during `MacDown2Tests`/UI tests is not covered by the fix (they passed 3/3); the issue stays open until a longer soak shows no stall; WebKit-specific behaviour not otherwise explained |
| H5 | #203 | Size-based Markdown highlighting fallback (bounded containment, 2026-10-15, `highlight-fallback`). Above 8,192 UTF-16 units there is no tree-sitter parser on open, restore, reload or Save As, and the edit that crosses the cut-off is withheld from Neon before its synchronous reparse. Exact-head Release benchmark (`2576414c`, quiet machine): with the fallback, a one-character edit in a reduced document (12 KB–4 MB) has p50 ≤ 1.1 ms and p95 ≤ 9 ms in 100 of 102 reduced-mode cells (105 logged; the 3 unicode 12 KB cells, 6,396 units, ran in full mode below the cut-off and are excluded). Pasting 1 MB costs a 7.6 ms stall; without the fallback the same paste stalls the main thread for 18.4 s. Details, the cut-off derivation and the reconciliation of the 3–9 ms and 6.2 s figures are in **H5 detail** below; evidence is in `planning/downstream/evidence/h5-highlight-fallback/` | PARTIAL (contained above the cut-off; #203 OPEN) | Below 8,192 units the keystroke cost is unchanged (≤ ~38 ms p95 measured at the nearest step, 8.4K units). Full highlighting of large Markdown documents still needs the dependency fixes (`planning/h5-dependency-followup.md`). The selection-replacement highlighting defect stays open (known issue). Preview and Outline are not addressed. The cut-off is measured on one Mac only |

## H5 detail: Markdown keystroke cost and the size-based fallback (2026-10-15)

**Earlier disposition: HISTORICAL, SUPERSEDED.** The row below is kept verbatim. The owner's option (a), the "size-dependent budget, 50 ms holds to ~384 KB", was based on the block grammar alone. PR #472 and the measurements here show the keystroke cost is dominated by the inline (`markdown_inline`) injection layer once it has been resolved over the whole document. Measured that way, 50 ms is exceeded at 16 KB of inline-dense text. The scope of the earlier measurement therefore changed (block grammar only vs. inline layer), and its conclusion no longer holds.

> HISTORICAL (superseded 2026-10-15): #388 corrected benchmark offsets and added a reuse control. Root cause proved (`MarkdownTreeReuseTests`): with a correct edit (≤ 1 changed range) the block grammar shares 0 of 1,489 old top-level sections after an edit at either end of a 64 KB document; JSON shares 2,133 of 2,134 with the same harness. The tree-sitter parse log (standalone C harness, vendored v0.5.3 sources, -O2) shows `paragraph`/`_line`/repeat nodes refused as `is_fragile` (conflicting reductions) and every later `section` refused by the first-leaf check (`atx_h1_marker` lexed in a state the reparse never re-enters); only leaf tokens are reused. Halving the edit's `Point` columns leaves the log identical; inline sublayer resolution (≈ 3–9 ms) and the viewport highlight query (≈ 1 ms) are negligible. Release-equivalent reparse after an EOF edit = 0.75 × full parse at every size: 15 ms @128 KB, 31 ms @256 KB, 64 ms @512 KB, 128 ms @1 MB; Swift Release `LanguageLayer.didChangeContent` at 1 MB 103–181 ms. Neon runs that reparse synchronously on the main actor for an edit ending before UTF-16 offset 1,048,576 | OPEN (cause PROVED; budget not met) | The cause is intrinsic to upstream tree-sitter-markdown, not fixable in this repo without patching the grammar. 50 ms is met up to ≈ 384 KB, not at 1 MB (gap ≈ 50–130 ms Release). **Owner decision requested**: (a) restate the E05 keystroke budget for Markdown as linear (≈ 0.13 ms/KB Release) with the 1 MB figure recorded as a known gap, or (b) size-based degradation — no tree-sitter highlighting for Markdown documents above a documented threshold (≈ 384 KB UTF-8 keeps a keystroke ≤ 50 ms); (b) must also cover reload and growth past the threshold while open **Owner disposition (2026-10-13): option (a).** The Markdown keystroke budget is restated as size-dependent (50 ms holds to ~384 KB; ≈0.13 ms per KB beyond, ≈130 ms at 1 MB in Release) and the 1 MB figure is a recorded known gap. The UI freeze at large sizes remains (Neon reparses synchronously on the main thread). **Planned follow-up (owner-requested direction):** limit tree-sitter work to what is displayed. Findings for that design: the viewport highlight query is ≈1 ms, the cost is the whole-document parse, and a window parse needs a safe block boundary (not inside a fence) because Markdown block structure depends on earlier lines. Preferred order: (1) parse off the main thread and highlight the viewport first, (2) window the parse from a safe boundary, (3) size-based degradation as a backstop. **Step 1 attempted (2026-10-13, PR on `perf-203-viewport-first`): not shipped; the premise changed.** (i) *Neon cannot be configured to reparse edits off the main thread*: the sync/async choice uses `static let synchronousLengthThreshold = 2048` / `synchronousDocumentSize = 1_048_576` on the internal `BackgroundingLanguageLayerTree`; neither `TextViewHighlighter.Configuration` nor `TreeSitterClient.Configuration` exposes them (upstream `main` unchanged). (ii) *The real keystroke cost is the inline injection, and it is superlinear* (Release, `StallFixtures` Markdown, one-character edit, `LanguageLayer.didChangeContent`): root block grammar only 8 / 33 / 133 / 530 ms at 64 KB / 256 KB / 1 MB / 4 MB (linear, matching the figures above); with the resolved `markdown_inline` sublayer 69 ms / 518 ms / 6.2 s / 203 s. Through the app's wiring (`KeystrokeStallBenchmarkTests`, 50 keystrokes, main-thread stall monitor) the shipped path stalls the main thread per keystroke: 64 KB median 66 ms (p95 83, max 124); 256 KB median 514 ms (p95 742, max 935); 1 MB median 6.25 s (p95 6.85 s, max 7.5 s); 4 MB not run through the editor (≈203 s per keystroke at the layer level). Likely cause (code reading, unverified — patching the dependency checkout was not permitted): tree-sitter `lexer.c` `ts_lexer_goto` scans all included ranges linearly on every lexer seek, so an injection layer with one range per paragraph is O(tokens × ranges); unchanged on tree-sitter `master`. (iii) *Experiment*: a test-only `EditWideningStorageDelegate` (between `NSTextStorage` and Neon's delegate) reports each edit with ≥ 2,048 units of unchanged context, which is a truthful edit and forces Neon's background path. It removes the per-keystroke stall (keystroke call max 2.9 / 6.1 / 10.1 ms, per-keystroke stall p95 81 / 3.0 / 2.0 ms at 64 KB / 256 KB / 1 MB) but is unshippable: (a) highlights diverge from a fresh highlighter (`NeonReplacementEditTests`), because every widened keystroke becomes a replacement containing whole inline ranges — see the finding below; (b) in Debug it aborts the test host with SwiftTreeSitter's 'location is greater than end'; (c) Neon queues one full reparse per keystroke without coalescing — 10 keystrokes at 1 MB leave highlights stale for 46 s, then one 284 ms main-thread restyle (the inline sublayer is also re-resolved synchronously on the main thread whenever the queue drains: 31–76 ms stalls at 64 KB). **Next steps (proposed, need owner/upstream decisions):** fix the included-range cost (tree-sitter `ts_lexer_goto` binary search; expected to bring a 1 MB keystroke from 6.2 s to roughly the 0.13 s root-only cost) and the SwiftTreeSitterLayer collapsed-range defect, both upstream or via a vendored fork; only then move the reparse off the main thread, with coalescing (Neon change to expose its thresholds, or our own `TreeSitterClient` replacement). Steps (2) window parse and (3) size-based degradation remain. |

**Setup:**
- Machine: Apple M3 Pro, 11 cores, 18 GB; macOS 26.5.1; Xcode 26.6; Swift 6.3.3.
- Dependencies: Neon `484d6fb9`, SwiftTreeSitter / SwiftTreeSitterLayer `cbe31cb3`, vendored TreeSitterMarkdown.
- Configuration: Release, serial. Every run started on a quiet machine, and a 5 s watcher logged no build or test process from another checkout during it. Runs that overlapped another agent's xcodebuild were discarded; they had read up to 10× high.
- Path measured: the real editor path (`EditorTextSystem` + `NeonSyntaxHighlighter`, inline injection resolved and verified by a styled inline run in the second half of the document).
- Workloads: ordinary prose, inline-dense, long lines (~6 KB per line), Unicode (CJK and emoji: UTF-8 bytes ≈ 2 × UTF-16 units) and fenced code.
- Edits: 16 one-character edits each at the start, middle and end, 50 ms apart.
- Reporting: stall (main-thread latency per edit) and settle (until highlighting stops changing) are reported separately.
- Evidence: `planning/downstream/evidence/h5-highlight-fallback/` (exact head `2576414c`).

**Measured observations:**
- **Full mode** (Neon unbounded, as shipped before H5): worst p95 per edit across the three positions. Sizes are UTF-8 bytes, with UTF-16 units in brackets.

| Size | Ordinary | Inline-dense | Long lines | Unicode | Fences |
|---|---|---|---|---|---|
| 8 KB | 35 ms | 32 ms | 43 ms [12.2K] | 16 ms [4.3K] | 13 ms |
| 12 KB | 22 ms | **43 ms** [12.4K] | 43 ms [18.3K] | 19 ms | 14 ms |
| 16 KB | 25 ms | **48 ms** | 51 ms [18.3K] | 38 ms [8.4K] | 18 ms |
| 32 KB | 35 ms | 88 ms | 65 ms | 41 ms [16.8K] | 26 ms |
| 64 KB | 134 ms | 175 ms | 71 ms | 65 ms | 37 ms |
| 128 KB | 86 ms | 669 ms | 19 ms | 116 ms | 54 ms |
| 256 KB | 193 ms | 1,936 ms (p50 1,788 ms; settle 1.7 s) | 17 ms | 258 ms | 101 ms |

  At 1 MB, ordinary text had p95 1,215 ms. Long lines at 128 KB and above, and inline-dense text at 1 MB, gave small stalls but long settle times: Neon had not processed those regions synchronously. That behaviour depends on the content and is not relied on.
- **Reduced mode** (shipped policy) at 12 KB–4 MB, five workloads:
  - Edits: p50 ≤ 1.1 ms; p95 ≤ 9 ms in 100 of 102 cells. The two outliers were 30.5 ms (the first editor created in the process) and 94.7 ms (one stall outside the edit call, whose own maximum was 5.2 ms).
  - Settle: 0 ms; nothing is styled.
  - First open: 3–33 ms, 46 ms for 1 MB of Unicode (548K units), 108 ms for 4 MB of Unicode (2.2M units), and 286 ms for the first editor created in the process. This is text-system setup; no parser is built.
- **Typing across the cut-off** (12 characters, one crossing): p95/max 20 / 31 / 28 ms (ordinary / inline-dense / Unicode). This is the cost of a sub-cut-off reparse.
- **Paste across the cut-off** into a highlighted document of ~8,000 units:

| Paste | With fallback | Without fallback |
|---|---|---|
| 256 KB | 16.9 ms stall; presentation cleared ≈ 20 ms after the paste; typing afterwards p95 1.6 ms | 571 ms stall, settles in 1.1 s; typing afterwards p50 609 ms |
| 1 MB | 7.6 ms stall; typing afterwards p95 1.0 ms | 18.4 s stall, settles in 20.8 s; typing afterwards p50 2.46 s |
| 4 MB | 21.3 ms stall; typing afterwards p95 2.3 ms | not run |

  No highlighter styled anything after a paste with the fallback.

**Reconciliation of the earlier 3–9 ms figure with 6.2 s** (`InlineResolutionReconciliationTests`, `LanguageLayer` level, one-character edit at 64 KB / 256 KB / 1 MB):
- Resolving the inline injection over a 4 KB viewport takes 4–6 ms at every size. That is the earlier "≈ 3–9 ms" quantity.
- An edit with only the root grammar, or only a viewport resolved, costs 2–5 / 9–26 / 42–124 ms.
- Once the inline layer has been resolved over the whole document, the same edit costs 50 / 421 / 5,091 ms (heading-line workload) and 62 / 500 / 5,985 ms (stall-block workload). Neon resolves the whole document because `TextViewHighlighter.init` validates `.all`.
- Re-resolving just the edited range afterwards costs about the same again.
- Both earlier figures were correct for what they measured: one measured a viewport, the other the whole document.

**Reproduced causes:**
- The inline layer's per-edit cost grows faster than document size, but only once it has been resolved over the whole document.
- Neon reparses an edit under 2,048 units that ends before offset 1,048,576 synchronously on the main thread, and that limit cannot be configured.
- The selection-replacement inline divergence (`NeonReplacementEditTests`, known issue) is unchanged.

**Proposed explanations (not verified):**
- tree-sitter's `ts_lexer_goto` scans every included range linearly, so a reparse costs about O(tokens × ranges).
- The collapsed or overlapping included ranges in `SwiftTreeSitterLayer.encorporateRanges` are rejected silently.

Plan only, with no speed-up claimed: `planning/h5-dependency-followup.md`.

**Fallback behaviour** (`HighlightingState`, `HighlightingSizePolicy`, `HighlightingStorageGate`, `NeonSyntaxHighlighter+SizeFallback`):
- **Cut-off:** 8,192 UTF-16 code units (`NSTextStorage.length`; O(1) per edit, no rescan or UTF-8 count). Restore happens at or below 6,144 units after 2 s with no edits. The hysteresis means editing around the cut-off never rebuilds the parser. Markdown only; other grammars were not measured and are unbounded.
- **Surviving work of a discarded highlighter (reproduced, measured, bounded; not zero):** Neon cannot cancel queued work, and its validator never goes stale (the content version is `NSTextStorage.hashValue`, the object's identity), so a validation already queued when the cut-off is crossed still runs once on the main actor. `StaleWorkAfterCrossingTests` reproduces it by crossing in the same main-actor turn as the highlighter's creation (open-and-cross) and as a 2,100-unit background-sized edit. Counters: ~23–26k stale styling requests, refused by the generation check (the document stays plain and no token is styled; disabling the generation check fails the open-and-cross and large-edit-then-cross tests, checked by hand against the earlier revision of those tests), plus 2–5 stale layer requests, now refused too (`LayerRequestState`, lock-protected because Neon calls the language provider on its background queue; unit-tested, the wiring itself is covered by the stale-count assertions only). Cost, Release (M3 Pro): longest main-actor gap 44–46 ms vs 19.5 ms for a quiet-document control, i.e. about 25 ms extra, and the stale count was 23k and 26k in two different scenarios (200K-unit and 400K-unit pastes; not a controlled size sweep, so independence from paste size is not established). Debug: 135–210 ms vs 27 ms for the control. So: queued work is *discarded after it starts*, not prevented, and one already-executing batch cannot be interrupted. The window is the few milliseconds after open or after a ≥2,048-unit edit; the fallback does not guarantee a zero-stall crossing there. A pending restore timer can build a parser for a closed tab until the window closes (store eviction is per window).
- **Cut-off derivation:** in the exact-head data, every workload and position stayed ≤ 50 ms at p95 up to about 16,400 units (inline-dense p95 48.0 ms). Long lines at about 18,300 units reached 50.8 ms. The cut-off is a conservative step well below that, about 8,400 units (worst measured cell: unicode, p95 38.2 ms), rounded down to 8,192 for slower Macs and denser text. 128 KB was not used as a threshold.
- **State:** the requested language and format are unchanged. `state` reports full / plain / reduced plus the reason.
- **No parser for an oversized document** on open, session restore, reload or Save As (`configure(languageID:)`; tested).
- **Where the crossing edit is intercepted:**
  - The gate occupies `NSTextStorage.delegate` in front of Neon's delegate. It decides in `willProcessEditing`, using the post-edit length, before Neon's `willProcessEditing` (which records the edit) and `didProcessEditing` (which reparses).
  - Proof: a recording stand-in behind the gate receives 0 callbacks for the crossing edit (`theCrossingEditNeverReachesNeon`). The gate's counters show the edit was seen but not forwarded.
  - The same path covers typing, paste, replace-all, undo/redo, external replacement and IME composition, each tested.
- **Teardown:**
  - Neon offers no way to cancel work. A discarded highlighter's late callbacks still run, but its attribute provider checks a generation and styles nothing (tested with queued work in Debug: no crash, no styling).
  - Only the highlighter-owned rendering attributes (colour, font, underline) are removed, after `processEditing` and outside any marked text.
  - Content, storage attributes, undo, selection and the previous storage delegate are preserved, each asserted by a test. Rendering attributes produce no storage edit, so no notification loop.
- **Non-modal note:** "Highlighting reduced" in the status bar, with an explanation in its help text, or in the editor corner when the status bar is hidden.

**Limits and what remains:**
- #203 stays OPEN. Documents of 8–16 K units, which previously met the budget for most text, are now plain.
- Below the cut-off, the keystroke cost is unchanged.
- A discarded `TreeSitterClient` is probably retained by Neon's internal closures. This was already the case for `setLanguage`.
- The cut-off was measured on one M3 Pro.
- Preview and Outline use their own debounced (150 ms) swift-markdown parse on the `ParseEngine` actor plus main-thread rendering. They are **not** addressed, and no claim is made about their performance.
- The dependency correctness investigation is separate (`planning/h5-dependency-followup.md`).

## Safety families (handoff A–G)

Not yet proved at their required layer unless listed. The rows below are the starting inventory; each needs the native or fault-injection layer the handoff names.

| Family | Owner | Status | Notes |
| --- | --- | --- | --- |
| A Exact source and truthful save outcomes | #183, FileStore | PARTIAL | Exact-scalar comparisons and encoding lineage covered by unit tests; no full matrix over Save / Save As / Replace in Folder / recovery / export with independent byte reads |
| B Conditional publication and competing writers | FileStore | PARTIAL | RENAME_SWAP fallback ownership, read-back/rollback and `conditionalPublicationRecoveryRequired` have unit coverage; Save As baseline vs external create and rename-during-publication schedules not re-verified here |
| C Metadata and private staging | #174 contract | OPEN | Staging privacy from the first byte is not measured natively; `carryMetadata` runs after staging data is created (source observation, not a demonstrated exposure) |
| D Recovery and session lifecycle | #183 | PARTIAL | See R1–R4; two-snapshot reverse-order publishers, relaunch/retry after each journal transition and the failed-save-then-later-edit schedule are not exercised here |
| E Root authority and contained resource reads | #121 | PARTIAL | RESOURCE-OPEN probe executed on macOS 26.5.1 / SDK 26.5 (`planning/downstream/evidence/resource-open/`): static and pin-then-swap schedules contain, no sentinel leak. `LocalResourceAccess` stage A (#121-A): pinned-descriptor reader with real-filesystem containment tests (leaf/intermediate swap between hint and open, root redirect, ancestor rename mid-read, FIFO, oversize/growth, cancellation between chunks, descriptor baseline, close-during-read); removing the open flags fails the two swap tests. Independent Opus review (different model from the author) found no outside-read path; its P2/P3 findings (directory pin without no-follow, grapheme-based parsing, `//authority`, `Int.max` cap trap, undischarged change-during-read and close-under-use tests) are fixed in #401 with discriminating mutations. 2026-10-18: the [bounded coordinator correction](downstream/evidence/preview-121-2026-10-18/README.md) adds exact navigation/view identity, queued-attempt recovery controls and a simple real WebKit render on a293e397. Delayed-root confusion and post-stop delivery remain reproduced. Not yet: other OS patch levels / 26.0, barrier inside the kernel path walk, the bounded I/O executor and quotas (stage C), immutable contexts (B), caller refactor and complete hostile/native WebKit proof |
| F Destructive folder actions and export ownership | #118 | OPEN | Not started beyond existing unit coverage |
| G Settings and state migration | #53 | PARTIAL | #400: `EditorSettings` compatible decoding (pre-E22 blob keeps every value, only the missing `showsStatusBar` defaults, range validation), unreadable/newer-version blobs retained verbatim, reported and copied once before any overwrite; 9 tests, discriminating mutation. Not yet: other domains as fields are added, UI surfacing of the report, journaled legacy import |

## Rejected-finding ledger

- JSON-format guard uses canonical `!=` (pass-10 suspicion): rejected — `JSONFormatter` preserves scalars (probe: U+212B kept), so a canonically-equal-but-scalar-different result cannot arise.
- Descriptor-count tests should use `==` (review P3): not adopted — other suites run in-process in parallel; `<=` still exposes a leak.

## Not authorised by this work

Credentials or persistent access, signing/notarisation, source-archive publication, deployment, repository cutover and public promotion. #147 (adopted) and `planning/RELEASE_SEQUENCE.md` define the order; the specific authorisation needed will be named when a dependent step is reached.

## Next bounded steps

1. #121 stages B–D (immutable contexts, bounded executor with cancellable `readlinkat` hint, quotas, WebKit proof).
2. Native UI run (`MacDown2UITests`) and native corroboration for R1/R2/R4/R5/R6.
3. Release performance tests; #203 owner decision (grammar investigation vs measured budget).
4. Native UI run (`MacDown2UITests`), native input-method corroboration and a Release performance run are the next bounded steps (owner-approved); the software gate for `b848deaa` is assessed in the handoff report; the final-release gates remain open

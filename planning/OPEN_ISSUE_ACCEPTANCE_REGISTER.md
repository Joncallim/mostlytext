# MostlyText open-issue acceptance register

## Issue reconciliation — 1 November 2026

All 18 remaining issues were inspected against live GitHub state, merged source
and their recorded acceptance criteria. Seventeen issue bodies now distinguish
completed implementation/controls from remaining acceptance; 35 existing
criteria were checked, and #53's completed parser-model cleanup was recorded.
No whole issue met its closure criteria, so none was closed.

PRs #544, #545, #532, #543, #541 and #533 are merged into integration-final.
Implementation merge `54e78ab5` has exactly the source tree tested at `31344a7c`
by CI 41289671790: 3,038 package tests in 417 suites (two existing Neon known
issues), 535 app tests in 110 suites, Debug/Release app and CLI builds, test
compilation, lint, Compliance and locked-resolution verification passed. Master
remains `15c0fae2`. This documentation reconciliation changes no runtime input.

Earlier #532/#543 runs failed the same intermittent session-publication
assertions. Their logs remain preserved under #183; the passing stack is not
claimed to identify those historical callbacks. PR #533 acknowledges current
startup monitoring before its controlled recovery gates and proves the late
baseline observation's safe rejection separately. It also awaits the owned
viewport restoration task instead of assuming completion within 150 ms. Both
publication cases, repeated invalidation and the offscreen viewport control
passed. Production guards, two-attempt limit and timer delays are unchanged.

PR #519 retains its explicit native folder-panel/WebKit/signed-app hold. PR #520
retains the architecture's source/native presentation hold; its diagnostic runs
are not a native pass. Quick Look, the complete legacy/state migration, native
UI/runtime isolation, Release performance, final localization and exact signed
artifact/source-offer qualification remain open in their owning issues. No local
app/UI test or public release was performed by this reconciliation.

## Earlier resumption checkpoint — 1 November 2026

The owner requested resumption of all work independent of Daybreak hardware-key
authentication. Live application master remains
`15c0fae22f7618e94c82681227057c66011be2a9`; integration is
`9de81f5ff5222138a210472f2def33de01df6c8c`. GitHub has 18 open application
issues. Older counts, pause statements and branch baselines below are historical.
The existing release sequence, performance budgets and acceptance rules remain
binding; no issue or native journey is waived by this checkpoint.

| Work | Current evidence | Remaining boundary |
| --- | --- | --- |
| [CLI foundations #546](https://github.com/Joncallim/macdown_2/pull/546) | 71 locked CommandBridge tests and the Release CommandBridge target pass with unchanged source hashes. Framing, requests, replies, retained receipts, endpoint leases, peer checks and bounded connected-socket I/O are implemented. | Actual listener/connect orchestration, request admission workers, public arguments, document/window admission, bootstrap migration, updater and native CLI evidence remain. |
| [Scanner backport #547](https://github.com/Joncallim/macdown_2/pull/547) | Exact upstream scanner bytes, corrected attribution/notices/SBOM and 36 focused package tests in seven suites. Combined immutable snapshot builds the Release app/CLI and Debug test targets with locked dependencies and unchanged inputs. | Independent integration review, native editor acceptance and the separate #203 performance target remain. |
| [Recent-file completion #548](https://github.com/Joncallim/macdown_2/pull/548) | Tests await the existing open task and retire all fixture controllers. Combined snapshot compilation passes. | Hosted execution must establish the actual corrected outcome. Settings #545's previous 515-test app run failed two recent-file assertions; that failure is retained. |
| Existing theme/settings/isolation drafts | #544 and #543 had passing hosted checks at resumption. #545 passed package/build stages but failed the app-target run described above. | Each draft retains its own native, review and owning-issue criteria. A source/build check is not acceptance. |

Local command evidence is retained under `CORTANA-Builds/resume-20261101-*` on
the Fast SSD. The application compilation receipt is
`resume-20261101-scanner-recent-app/receipt.json`; it records both source
overlays and zero application tests run. CLI evidence is
`resume-20261101-command-replies/receipt-socket-io-final.json`. Initial failed
controls remain beside corrected results. Hosted results are read from each
PR's actual tested head rather than inferred from these local passes.

The separate non-admin `mostlytexttest` account exists as UID 502. A live
`launchctl print gui/502` check found no GUI bootstrap. Local app/native runs
therefore remain NOT_RUN until the safe GUI lane and positive control are
verified. Daybreak session authentication and macOS GUI authentication are
separate dependencies. Neither blocks ordinary source implementation, package
tests or build verification. The owner will handle the hardware key separately.

Continue #18 transport/admission and #53's serialized migration writer, then
the remaining #113 application integration and #148 attribution work under their
existing contracts. Source review, actual native outcomes, linguistic review,
exact signed-artifact qualification and action-specific publication approval
remain required before final issue closure or public delivery.

## Historical execution baseline — 1 November 2026

The owner approved the complete macOS 1.0 convergence plan and implementation.
Live `master` is `15c0fae22f7618e94c82681227057c66011be2a9`; live
`integration-final` is `7b8b4055796d7452fc6dd1b27ced71470c92623c` (21 commits
ahead, none behind master). There are 18 open application issues and five draft
application PRs. Earlier counts, pause statements and branch checkpoints below
are historical. Existing safety/review/evidence gates remain required.

The [execution contract](downstream/COMPLETION_EXECUTION_2026-11-01.md) records
the approved scope, dependency order, current native-test isolation incident,
and release boundaries. Source changes begin with #88's startup guard and
non-launch verification. No candidate has passed the complete final native
matrix. The earlier private #88 source and patches were preserved on the Fast
SSD before importing them; the original checkout remains untouched.

## Historical owner summary


MostlyText has 22 open issues. The integration candidate is locally preserved on
`fix/ci-timing-contracts`; it is not approved for merging or release. The immediate
work corrected timing assertions, restored the original whole-call cleanup bound,
retired a leaking benchmark window and corrected actor isolation in test suites.
The final code still has failed Release parser and editing-assist performance
measurements. Separate source review found no concrete regression, with explicit
coverage limits; owner acceptance remains pending. The
highlighting cutoff and production dependency pins remain unchanged. Editors
retain the existing reduced-highlighting behavior and the previously integrated
repaint correction. No new product capability is claimed.

This register connects every open issue to its remaining outcome and next bounded
step. It is an intake and execution map, **not** a completed closure audit. The
[criteria snapshot](downstream/open-issue-criteria-2026-10-18.json) preserves all
285 issue-body checkbox entries, source checkbox states, issue/comment dates and
content hashes. Prose requirements and comments remain binding; unchecked boxes
are not evidence of absent code, and checked boxes are not evidence of final
verification. Raw issue bodies and all comments are retained with the local logs.

Source inspected: `0b85e6f09dc3bba82a0da3b15f1583b3263fcb74`, based on clean
integration `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`. Master remains
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`; dependency experiments remain isolated
on `dep-trial` at `29e08843325bd744fb2cd5ea5abccf96dc22fb57` (the later handoff-only
commit acknowledges transfer of the integration worktree). The new local
changes have no hosted CI result. See the [timing investigation](downstream/evidence/ci-timing-2026-10-18/README.md)
and the [follow-up validation](downstream/evidence/ci-timing-2026-10-18/FOLLOWUP.md)
for exact-head outcomes and unresolved failures. The later
[independent review and fixed diagnostic](downstream/evidence/ci-timing-2026-10-18/INDEPENDENT_REVIEW.md)
cover documentation checkpoint `e16be9f7`, whose code matches `0b85e6f0`.

The subsequent [Mermaid artifact audit](../compliance/evidence/mermaid-11.17.2/README.md)
started at `40b25974`. It closes the missing bundle/source-map linkage and records
mapped modules and captured package texts, with independent review. It remains
partial for nested attribution, does not change distributed notices or product
code, and does not supersede either failed performance measurement.

The following [#53 reconciliation](downstream/evidence/settings-53-2026-10-18/README.md)
starts from `d3cc8883`. It fixes the reproduced distinction between an absent
status-bar field and explicit JSON null, and adds declaration coverage for the
legacy key table. An isolated probe documented the historical write-protection gaps:
only the first unreadable Data generation was backed up, and non-Data values were
not reported. The later [protected-write correction](downstream/SETTINGS_WRITE_PROTECTION_2026-10-19.md)
addresses those ordinary-write losses. Neither slice completes migration or waives #53's criteria.

The subsequent [#121 callback correction](downstream/evidence/preview-121-2026-10-18/README.md)
starts from `a4c48bc7`. It binds callbacks to their navigation/view and separates
queued attempts from process recovery. Retained baseline and review regressions,
negative controls and a simple real WebKit render support that bounded fix.
Mutable resource-root confusion and post-stop delivery were also reproduced and
remain open; no resource-authority or full native release claim follows.

The [combined overnight checkpoint](downstream/OVERNIGHT_CHECKPOINT_2026-10-18.md)
and [one-shot validation record](downstream/evidence/overnight-consolidation-2026-10-18/README.md)
cover clean `400d475caaae130cdce1f6de4c6904027e700827`, including stop-aware
resource delivery, settings validation and licence packaging. Serial package and
app-target non-performance gates, Debug/Release app and CLI builds, and ordinary
source/artifact compliance pass. Two existing Neon known issues, two disabled
interactive PDF tests, persistent build/runtime diagnostics and seven release
compliance findings remain explicit. Independent review of the complete overnight
diff found no new material interaction defect. This consolidation reran no
performance suites, supplied no native UI/CJK acceptance and changed no remote
state; earlier performance and hosted failures remain binding. The minimum next
owner decisions concern the file-only asset workflow and shipping OS-access
configuration. The later documentation commit preserves exact source equivalence
to this tested head; it does not replace the recorded build provenance.

## Evidence rules

- **Source:** implementation or a gap inspected in this candidate. This alone
  does not prove the user journey.
- **Local:** command, environment, exact commit and outcome recorded together.
  Mutation failures are negative controls, not passing validation.
- **Hosted:** GitHub's actual tested checkout, including its synthetic merge
  commit, is recorded. Local passes do not overwrite hosted failures.
- **Native/manual:** the real window/input method/artifact and exercised path are
  named. Building a UI test does not execute it. The Simplified Pinyin evidence
  is Debug-only and does not establish automated CJK coverage.
- **Historical:** older observations remain useful but are not relabelled as
  proof for this candidate. Independent review and owner acceptance stay distinct
  from an author's tests or source inspection.

## Every open issue

| Issue | Current evidence and remaining outcome | Next bounded step |
| --- | --- | --- |
| [#17 Localization](https://github.com/Joncallim/macdown_2/issues/17) | Package-localized file-operation errors use the module bundle in inspected source. Final resource audit, French/Japanese native review, plural/layout checks and string freeze remain unverified. | Follow the E16 handoff after private candidate 1; retain a small current-source string/resource inventory before changing catalogs. |
| [#18 Distribution and migration](https://github.com/Joncallim/macdown_2/issues/18) | Release scripts exist, but the inspected project still uses development identity/version and CLI `macdown2`. Final migration, updater, install/update rehearsal and exact signed artifacts remain open. | Rebaseline application-side architecture against final settings/themes and frozen MostlyText identity. Prepare locally; signing, notarisation and publication are explicitly outside current authorization. |
| [#53 Preferences and Markdown options](https://github.com/Joncallim/macdown_2/issues/53) | Missing-field compatibility was already implemented; explicit null is now rejected after a baseline reproduction. A source-pinned record/checker covers 52 stored, four calculated and two transient legacy declarations, with six unproved destination candidates. The 19 October protected-write correction retains every unreadable primary value during ordinary settings writes and reports non-Data values too; affected changes apply only to the session with a Settings warning. The original losses remain in baseline evidence. | The bounded ordinary-write contract is now reconciled; verify the exact combined candidate and keep explicit recovery/import execution separate. Complete conversions, precedence, consent, idempotence and E23 destinations; declaration coverage alone cannot close this issue. Use isolated fixtures only. |
| [#79 Diagram appearance](https://github.com/Joncallim/macdown_2/issues/79) | Integration uses a neutral-light presentation. PRs #476/#477 offer theme-dependent alternatives; D2, print/PDF contrast and the cross-engine policy still need reconciliation. | Recommend retaining the neutral representation until the owner accepts an explicit policy compatible with E23 and #79. Compare alternatives without merging conflicting behavior. |
| [#88 Native UI coverage](https://github.com/Joncallim/macdown_2/issues/88) | Historical native passes and the bounded Simplified Pinyin manual record exist. Final E22/E23 critical flows, other input methods, candidate mouse interaction and long composition during restore are not proved. Six UI suites and two app-test suites now have corrected actor isolation; the final app-owned compiler commands pass with Swift warnings treated as errors. Native UI execution remains unverified on this code. | Freeze the actual final software candidate, then execute the finite critical UI matrix in an explicitly available desktop session. |
| [#112 Editor essentials](https://github.com/Joncallim/macdown_2/issues/112) | Much of E22 and subsequent hardening is implemented. Its performance, settings, recovery, native interaction and audit acceptance is not complete merely because feature code landed. | Reconcile each E22 criterion with #183 and the dependency-specific records; repair one reproducible gap at a time with negative controls. |
| [#113 Themes, Quick Look and Finder](https://github.com/Joncallim/macdown_2/issues/113) | Two bundled Tomorrow themes exist; the inspected XcodeGen spec has no Quick Look target. The full theme set, safe custom themes, shared static presentation and Finder integration remain product work. | Rebaseline the post-E22 architecture using frozen identity inputs and the safe resource/anchor contracts; satisfy Definition of Ready before broad implementation. |
| [#115 Debt gate](https://github.com/Joncallim/macdown_2/issues/115) | Umbrella release acceptance remains open. Older package/app/UI passes are historical, not a substitute for all owning issues or exact-artifact proof. | Follow software stabilization → private candidate 1 → final localization → candidate 2 and artifact-sensitive reruns. No administrative closure on CI alone. |
| [#116 Math correctness/accessibility](https://github.com/Joncallim/macdown_2/issues/116) | Scanner/contribution components exist. Complete syntax/escaping, diagnostics, equation-level navigation, accessible equations and native visual/performance/parity proof remain. | Follow the math handoff: discriminating syntax cases and adapter probe before integrating presentation behavior. |
| [#117 Contributions, anchors and palette](https://github.com/Joncallim/macdown_2/issues/117) | Generic representations exist, preview admission still rejects HTML, and TOC output is plain text. Shared anchors, clickable destinations, capability policy, palette consistency and explicit export targeting require complete evidence. | Execute shared anchor/parser capability probes; update the accepted contract before changing preview/export consumers. |
| [#118 Export safety and fidelity](https://github.com/Joncallim/macdown_2/issues/118) | Export infrastructure exists, but current-source coverage is not a complete closure audit. F06/F13 output-authority cases, resources, parity, real PDF print behavior, budgets, cancellation and recovery remain required. | Reconcile the export handoff against source, then prove one opened-resource/output-publication boundary with hostile schedules before broad refactoring. |
| [#119 External-file evidence](https://github.com/Joncallim/macdown_2/issues/119) | Existing automated coverage does not supply the full native external-change matrix or Release watcher/digest/latency measurements. | Run the documented Release manual/performance matrix with independent byte reads, selection/scroll observations and watcher/wakeup evidence on the chosen candidate. |
| [#120 Open/Save interaction](https://github.com/Joncallim/macdown_2/issues/120) | Source has saving state and a destination-aware close-sheet label. End-to-end Save As progress, changing backing-file state and large-file Open latency remain unverified. | Exercise native Save As/close paths and measure Open before deciding whether another code fix is required. |
| [#121 HTML preview authority](https://github.com/Joncallim/macdown_2/issues/121) | Safe local-resource opening stage A and MIME handling exist. Exact navigation/view callback ownership and stop-aware delivery have local regression evidence on 7efb510c. Delayed A still reads root B in the retained reproduction. The independently reviewed directory-grant proposal remains blocked on the file-only asset workflow and intended OS-access configuration. | Resolve that permission/compatibility boundary before immutable contexts and contained child-directory acquisition. Retain worker/payload, off-main I/O, Save As, scope cleanup and full native hostile-corpus requirements. Neither the callback correction nor the proposal completes this issue. |
| [#148 Licensing/provenance](https://github.com/Joncallim/macdown_2/issues/148) | Mermaid's shipped bytes match the official archive/map, but deeper prebundle attributions and 3,980 unmapped parser positions remain unresolved. The KEEP-all-12 font decision is reconciled. A complete byte audit now accounts for Textual's Prism payload and preserves both MIT texts. Clean candidate `ceecea9c` packages LICENSE/generated notices and passes ordinary unsigned artifact compliance; the earlier three-failure artifact record is retained. All 12 font digests remain present, and seven release findings remain. | Complete the remaining attribution audits and already-planned licence UI. Preserve all seven release findings, final signed-artifact verification and owner acceptance. Keep D2/Graphviz preparation and Tomorrow Light's E23 decision separate. Source-only publication still requires specific authorization. |
| [#155 Test hangs](https://github.com/Joncallim/macdown_2/issues/155) | Later discussion and #421 identify AppKit window animations exhausting dispatch workers in a reproduced schedule. This is stronger than the stale issue title, but does not explain every WebKit hang. | The later 103.099-second close delay has a reproduced contributor: the cache benchmark retained its real window and background work. A teardown regression fails without retirement; the final full-run close case takes 0.601 seconds. Investigate the remaining AppKit/SwiftUI update warnings and audit other fixture windows before a bounded native soak. This does not close every hang criterion. |
| [#158 Identity/cutover](https://github.com/Joncallim/macdown_2/issues/158) | MostlyText name, bundle prefix, CLI name, brand assets and MIT choice are frozen. Runtime migration and final repository/public-copy cutover are separate pending work. | Consume frozen inputs in E17/E23. Keep the full-history repository mirror late, after #115; do not rename or transfer the backlog early. |
| [#159 Fixture ownership](https://github.com/Joncallim/macdown_2/issues/159) | Integration contains typed readiness and bounded fixture ownership. The [reviewed timing correction](downstream/evidence/ci-timing-2026-10-19/README.md) anchors cleanup to an absolute deadline before cancellation/watchdog dispatch, retains the original 150 ms whole-call and cleanup bounds, and proves actual aggregate cancellation with a negative control. Real-clock style comparisons remain separate from deterministic idle-contract checks. Focused local evidence does not explain historical hosted styled-run mismatches or establish a combined Release pass. | The [cancellation-isolation correction](downstream/evidence/cleanup-cancellation-2026-10-19/README.md) addresses a separately reproduced cooperative-executor blockage and retains the 150 ms bounds. Hosted late-sleep overruns remain unexplained. PR #492/#473 were administratively superseded by #493 with evidence retained; validate the exact corrected combined candidate and obtain owner acceptance before issue closure. |
| [#173 Native navigation](https://github.com/Joncallim/macdown_2/issues/173) | Native activation already exists; the integration work adds lifecycle/currentness protections. PR #474 is an alternative with overlap, not an automatic missing feature. | Verify actual visible reveal below the viewport, tab activation and stale asynchronous intent on the native app; compare alternatives before adopting one. |
| [#183 Merged-code audit](https://github.com/Joncallim/macdown_2/issues/183) | Many original findings have subsequent fixes, while `CLOSURE_REGISTER.md` still records partial safety families and native/fault-injection gaps. Old source findings must not be reported as current without rechecking. | Build criterion-to-source/test/native mappings for F01–F23 and later review additions; take the first still-reproducible bounded defect, preserving exact scalar and lifetime invariants. |
| [#203 Large Markdown latency](https://github.com/Joncallim/macdown_2/issues/203) | The 8,192 UTF-16 fallback contains known stalls by reducing highlighting. It does not satisfy the original fully highlighted 1 MB budget. Dependency experiments remain isolated and unadopted. The second final planned Release series run failed the direct 1 MB parser ceiling at 484.814584 ms versus 400 ms; its cause remains unestablished. | Keep the cutoff/pins. Continue the measured grammar/dependency investigation only under its reviewed contract; verify edits and correctness before any adoption. Keep open. |
| [#459 Highlighting correctness](https://github.com/Joncallim/macdown_2/issues/459) | Debug abort/edit-geometry defects and some corrections are documented. Disabling assertions in Release is not proof of correctness; mounted lifecycle/stale-token and Unicode evidence remains incomplete. | Reconcile the proposed architecture in PR #462 and the dependency experiment with current integration; reproduce the remaining schedule on real Debug and Release editors before changing dependencies. |

## Sequence and concrete review gates

1. **Finish this integration checkpoint.** Separate source review through
   `e16be9f7` found no concrete regression. Preserve the failed Release parser
   ceiling and subsequent 56.881709 ms editing-assist result against 50 ms; the
   fixed context experiment stopped on that new failure without proving a cause.
   Address remaining runtime/build-tool diagnostics and owner acceptance, then obtain
   authorization to push the reviewed branch for fresh hosted CI. The exact proposed
   external change is a fast-forward of remote `integration-final` from `60f779fc`
   to the accepted local tip; it has not been performed. PR #480 stays draft/unmerged.
2. **Complete remaining E22 and safety work in small slices.** Prefer #121's
   already-documented request-lifetime slice and discriminating #183 regressions;
   do not treat the architecture-readiness graph as implementation evidence.
   Rebaseline the relevant handoff before any changed cross-module dependency.
3. **Complete dependent product work.** Settings compatibility precedes migration
   writers; the theme and shared resource/anchor contracts precede E23 consumers.
   Implement E17 application behavior before software stabilization. Keep native
   evidence tasks alongside the code they assess.
4. **Follow the adopted two-candidate sequence.**
   [RELEASE_SEQUENCE.md](RELEASE_SEQUENCE.md) supersedes older single-candidate
   sequencing in issue prose and old status paragraphs. It does not waive their
   acceptance requirements. #115 remains open through final localization and
   final-artifact compliance/reruns; repository cutover and public promotion are
   later, separate authorizations.

The seven current release-preflight failures are: D2 anonymous source location;
D2 Go and embedded-WASM license/source inventory; Mermaid bundled npm provenance;
Tomorrow Light naming/provenance decision;
Viz/Graphviz anonymous source location; exact Graphviz 16.0.0/Viz 3.30.0 source,
build instructions and hashes; and Graphviz-linked library confirmation.
The [2026-10-18 font reconciliation](../compliance/evidence/swiftui-math-fonts-2026-10-18/README.md)
records the existing KEEP-all-12 decision and retains all resource and licence
checks. Historical eight-failure evidence remains unchanged.
The earlier retained unsigned Release app from `7efb510c` had three additional
artifact failures: missing `LICENSE`, missing generated notices and unregistered
Textual `prism-bundle.js`. Its ten-finding record remains unchanged. The
[Prism audit and packaging correction](../compliance/evidence/prism-textual-1.29.0/README.md)
accounts for the exact bundled bytes and verifies both licence files at their
main-app resource paths in a fresh Release build of clean `ceecea9c`. Ordinary
artifact compliance now passes; source and artifact release checks still report
the same seven findings. This app has only the linker's ad hoc signature and no
sealed resources; it supplies no signed-release, native licence-UI or performance
acceptance evidence.
The generated, ignored `MacDown2/MacDown2/Info.plist` makes the working-directory
compliance scan report an unregistered distributed file. The clean `git archive`
source scan passes. This distinction is recorded rather than deleting or
registering a generated artifact to silence the check.

Recommended owner choices are concrete: retain neutral diagram presentation
until a reviewed cross-engine/print policy is accepted; preserve the 8,192 cutoff
and current lock while dependency correctness is unresolved; retain all currently
licensed fonts, following the KEEP decision already recorded in
[#148 comment 5868785863](https://github.com/Joncallim/macdown_2/issues/148#issuecomment-5868785863)
and now reconciled in `compliance/inventory.json`; and reconcile the
Tomorrow Light name with the recorded asset provenance rather than assuming a
name grants provenance. The font choice was already recorded; the other
recommendations do not adopt new policy.

## Branches and evidence to preserve

PRs #473/#474/#476/#477 overlap or conflict with integration and need deliberate
comparison. PR #475's change is already represented in integration history.
PR #472 is superseded evidence, but any external closure waits until integration
is accepted. PR #462 remains proposed architecture. The unmerged Pinyin UI branch
`4cc7a2622bab65213932e7164577562dbeaaae6a` is preserved; manual Pinyin evidence
has narrower coverage than automated input-method proof.

No issue was closed, no PR was changed, and no branch was pushed by this checkpoint.
No signing, notarisation, credential work, source/binary publication, upstream
submission, worktree deletion or repository cutover is authorized here. The owner
review remains pending. Separate source review of the local corrections through
`e16be9f7` is complete; it does not replace the failed performance or release gates.

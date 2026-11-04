# Remaining engineering and acceptance ownership — 4 November 2026

The live 4 November audit contains 17 open issues and 184 unchecked original
checkbox rows after PR51. Three issues use prose rather than checkbox criteria;
that does not make them complete. These are broad acceptance contracts, not
17 newly discovered bugs.
Merged implementation, automated checks and documentation progress are recorded
within them. None currently has all its whole-issue closure evidence. This map
reconciles current source, the transferred issues and the preserved native hold;
it is a work queue, not a declaration that engineering or release work is done.
Initial mapping baseline: main 8c78f3cd13635a7010ebeaecad932744afc90992.
Current fully qualified source baseline: main `8158068771a2012c27885d7ac4808cf73af7ffb1`
([PR51](https://github.com/Joncallim/mostlytext/pull/51)). Its actual tree matches
qualified `2ddfe206`; complete CI passes 3,422 package and 607 app tests. Scoped
source/resource evidence is recorded in [ACCEPTANCE_STATUS.md](ACCEPTANCE_STATUS.md)
and the associated PRs; the named remaining contracts below still apply. Historical PR numbers
resolve through [ISSUE_TRANSFER_MAP.md](ISSUE_TRANSFER_MAP.md).

## Work still requiring implementation or diagnosis

| Owner | Remaining work and completion evidence |
|---|---|
| [#6 editor](https://github.com/Joncallim/mostlytext/issues/6) | Reconcile the retained current-line/theme-role draft, actual multi-selection/editing behavior and remaining text workflows. Establish large-file/full-path Release budgets; a source scan microbenchmark is insufficient. |
| [#7 Mac integration](https://github.com/Joncallim/mostlytext/issues/7) | First pass the required native QL-REPLY callback/cancellation/cold-Finder feasibility probe, then implement the currently absent dedicated Quick Look target and static shared-content path, Markdown document artwork/registration, and remaining theme/renderer semantics. Verify containment, failure isolation and performance in real Finder/Quick Look. Naming conventions are frozen, not implementation. |
| [#9 math](https://github.com/Joncallim/mostlytext/issues/9) | Complete shared delimiter/parity, useful source-anchored diagnostics and accessible equation identity; prove final Preview/Export paths and real visual/accessibility behavior. |
| [#10 contributions/TOC](https://github.com/Joncallim/mostlytext/issues/10) | Activate/prove deterministic shared heading anchors and actual Preview/Export TOC navigation. Immutable parse ownership/source binding is integrated; that is not navigation acceptance. |
| [#11 export](https://github.com/Joncallim/mostlytext/issues/11) | The original managed-asset crash/orphan criterion is checked after [PR51](https://github.com/Joncallim/mostlytext/pull/51): [authenticated companion inventory/pending recovery](downstream/export-companion-recovery.md), first-inventory-before-cleanup ordering, changed-stage byte checks, source protection and bounded unknown-reference retention are qualified. Pre-receipt uncertainty is preserved and blocks growth. Remaining work is Preview/cmark parity, whole-operation PDF progress/cancellation, final resource-budget calibration, real pagination and exact-app Save/Cancel evidence. None is replaced by the 396 focused source tests or 100 changed exports. |
| [#13 HTML preview](https://github.com/Joncallim/mostlytext/issues/13) | The production consumer still uses the legacy handler. The bounded grant/handler must not be activated without the required native request/root/MIME/cancellation/containment proof. The preserved draft was closed without merge or acceptance. |
| [#14 attribution](https://github.com/Joncallim/mostlytext/issues/14) | Technical disposition of the final 100 parser references is complete with zero technical remainder. Independent embedded/generated IP/grant, D2/font/source and complete Graphviz per-file/runtime review and approved source publication remain. Captured Go 1.24.6 standard-library and compiler-rt texts are distributed conservatively; they do not waive those reviews. LC-08's original Help-menu entry now reuses the existing shared scene; genuine native menu/window acceptance remains separate. Captured package texts and conservative build-input notices now ship. |
| [#15 WebKit](https://github.com/Joncallim/mostlytext/issues/15) | Controlled extended-session reproduction/root-cause diagnosis remains. Hosted fixture/alert/IconServices corrections do not explain or close the original WebKit hang. Preserve failed-run samples; do not change timeouts or label a retry as a fix. |
| [#16 identity](https://github.com/Joncallim/mostlytext/issues/16) | The owner-approved social preview is installed and publicly verified; repository/backlog cutover and compiled document-rank/helper corrections are complete. Finish approved document artwork, native Finder/Open With, update-channel and installed-state evidence. Website source `0d04102` is ready but deployment approval remains pending. Retained internal/storage identifiers are intentional. |
| [#17 audit](https://github.com/Joncallim/mostlytext/issues/17) | Reconcile each directly owned finding with its exact fix/proof and each delegated finding with its owner. Repeat the final whole-repository review on the post-fix baseline and retain required native lifecycle proof. |
| [#18 parsing performance](https://github.com/Joncallim/mostlytext/issues/18) | Remaining whole-document work and genuine 1 MiB Release keystroke budget need resolution/proof. Retained measurements above budget are failures, not superseded by smaller component timings. |
| [#19 highlighting](https://github.com/Joncallim/mostlytext/issues/19) | Establish the original Debug abort's exact offset/limit trigger in a mounted editor; deterministic stale parse/style interleavings, UTF-16 edit geometry, lifecycle/IME and Release stress proof remain. Scanner safety fixes do not close all these paths. |

Each code unit still follows [EPIC_STANDARD.md](EPIC_STANDARD.md): current-source
architecture before broad edits, deterministic regressions, exact locked tests,
Release build and required native evidence. This map does not silently activate
held code, re-open product identity or introduce new features.

## Shared native, localization and release acceptance

| Owner | Remaining completion evidence |
|---|---|
| [#5 native UI](https://github.com/Joncallim/mostlytext/issues/5) | Protected staging, fresh source/build receipts and active separate GUI session, followed first by the genuine formatting-focus control and then the critical UI matrix. Owner-account product paths remain held. |
| [#12 external files](https://github.com/Joncallim/mostlytext/issues/12) | Exact Release reload/conflict/close, selection/scroll, filesystem storms, 1/10 MiB latency and idle-wakeup matrix, with genuine XCUITest execution. |
| [#3 localization](https://github.com/Joncallim/mostlytext/issues/3) | Post-software-stabilization string audit/freeze, translated/pseudo-localized layout, three plural-rule languages, VoiceOver/native-language review and exact string baseline. Do not freeze before remaining in-app UI/strings. |
| [#4 distribution](https://github.com/Joncallim/mostlytext/issues/4) | Coordinated public package/CLI naming, real clean/stateful install and idempotent migration, Sparkle feed/key/channel and N→N+1 state-preserving update, Developer ID signing, notary credential profile, notarization/stapling/Gatekeeper and exact final compliance. |
| [#8 closure gate](https://github.com/Joncallim/mostlytext/issues/8) | Consume all owning issues, zero release-relevant P0/P1/P2, final review, coherent evidence on one exact verification candidate and the localization/artifact handoff. It cannot close by aggregating source passes alone. |

Historical local prerequisite observations and current source checkpoints are
in [ACCEPTANCE_STATUS.md](ACCEPTANCE_STATUS.md). They do not authorize bypassing
the protected test-account boundary. The previously observed valid signing
identity does not supply the absent notarization profile or prove
any signing/installation journey. Native receipts bound to old source remain
historical and must not be retargeted to a new checkout.

## Attribution and publication order

1. Verify and distribute unambiguous captured texts; retain original copyright,
   complete terms and exact archive/source links. Keep content-matched candidate
   versions and conservative source-build attributions visibly qualified.
2. Resolve the remaining named/embedded/generated provenance. Framer's [historical intermediary match](../compliance/evidence/framer-spring-history/README.md)
   and [points-on-curve's traced source chain](../compliance/evidence/points-on-curve-origin/README.md)
   narrow the review without resolving the actual original grant. Ralf Thenable
   now has its expressly declared standard MIT terms assembled with the actual
   author credit and [mapped evidence](../compliance/evidence/thenable-mit-declaration/README.md);
   no standalone upstream license file is invented.
   The parser's [verified signed publisher provenance](../compliance/evidence/parser-publisher-provenance/README.md)
   and [complete JS/map reproduction](../compliance/evidence/parser-runtime-reproduction/README.md)
   establish the outer compiler and input version. The [qualified Webpack runtime
   notice](../compliance/evidence/webpack-parser-runtime/README.md) supplies four
   complete matching licensed bodies. The [final 100-reference syntax packet](../compliance/evidence/parser-residual-positions/README.md)
   leaves no technically unclassified reference; earlier nested builds and all
   original independent attribution/rights-review obligations remain separate.
3. Independently review complete corresponding-source and nested obligations,
   including D2's Liberation Mono Reserved Font Name and Graphviz compiler/runtime
   inputs. A local review archive is not independent review or an approved offer.
4. Prepare the concrete immutable source objects for approval. Only the explicit
   source-archive authorization in [ARCHIVE_PLAN.md](../compliance/ARCHIVE_PLAN.md)
   authorizes publication; public application promotion remains separate.
5. Verify anonymous retrieval and exact final signed artifact; preserve all six
   strict failures until their actual predicates pass. No count reduction is
   inferred from added notice records alone.

See [package notices](../compliance/evidence/mermaid-package-notices/README.md),
[build attributions](../compliance/evidence/nested-build-attribution/README.md),
[license window](../compliance/LICENCES_UI.md) and
[release sequence](RELEASE_SEQUENCE.md) for concrete evidence and boundaries.

## Named prerequisites for the next engineering units

Quick Look's binding [QL-REPLY probe](downstream/issue-113-handoff.md) first
requires a minimal installed signed/ad-hoc provider and real cold Finder
callback/fallback/cancellation evidence. Only after it passes may broad shared
rendering be integrated. This probe cannot be replaced by API compilation or a
mock callback. The protected native desktop/staging prerequisites are currently
unavailable; target absence remains unfinished implementation, not a completed
feature waiting only for a screenshot.

The held HTML-preview consumer, current-line drawing, mounted-editor geometry,
long-session WebKit diagnosis and real PDF/TOC lifecycle journeys likewise retain
their named native/reproduction prerequisites. Continue independent safe source
units where interfaces and evidence permit, but do not integrate those held
behaviors or weaken their gates merely to reduce the open-issue count.

[The attribution review packet](../compliance/UPSTREAM_REVIEW_QUESTIONS.md) records
the concrete missing upstream/independent-review inputs and available evidence.
It does not claim those questions have been externally submitted or resolved.

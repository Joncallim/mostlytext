# MacDown → Swift/SwiftUI Migration Plan

> Current product/source — 3 November 2026: MostlyText is the owner-frozen name;
> application history and open engineering backlog are in MostlyText/main, with
> website source separate. [Identity](IDENTITY.md), [acceptance status](ACCEPTANCE_STATUS.md)
> and [remaining engineering](ENGINEERING_REMAINDER.md) describe current source and
> unfinished requirements. Dated MacDown 2/master decisions below preserve lineage
> and original architecture; they are not current branding or acceptance claims.


> Status: **approved direction** · Scope: full rewrite as a **new product** · Target: **macOS 26+ for 1.0**

This document is the single source of truth for the rewrite roadmap. Epics live in
`planning/epics/` and are tracked as GitHub issues on `Joncallim/mostlytext`. Historical closed issues, PRs and
exact-source evidence remain in `Joncallim/macdown_2`; use
[the transfer map](ISSUE_TRANSFER_MAP.md) for imported bare issue numbers.
`planning/EPIC_STANDARD.md` defines the mandatory readiness, architecture,
execution, completion and human-readability contract for epic work.
`planning/RELEASE_HARDENING.md` defines binding cross-epic macOS 1.0 integration,
identity, offline/privacy, fidelity, evidence, localisation and release gates.

> **Amended 2026-07-22 (mid-point check-in, #28):** D2 reversed to native
> `NSWindow` tabs; branch strategy updated (`master`, not `rewrite/main`); O4
> resolved; EPIC-18 (live external-file changes) added as a required
> pre-dogfooding capability.
>
> **Amended 2026-08-16 (technical-writing/product-completion review):** math and
> text-authored diagrams became first-class macOS 1.0 capabilities; E14 was
> narrowed to contribution/extension infrastructure; E19-E21 own math/diagrams;
> a feature-complete gate precedes final polish; iPad implementation is deferred
> until after the completed macOS 1.0 release; final product naming was reopened.
>
> **Amended 2026-08-16 (cross-epic release-hardening review):** no new feature
> epics were added. The existing plan now freezes public identity before E15,
> uses one release-evidence/text-fidelity/UI-test gate, makes E12/E14 share a
> renderer-neutral Preview/Export contract, requires first-party features to work
> locally/offline, makes E21 renderer candidates individually admissible, makes
> E16 the in-app string freeze, and requires E17 to rehearse stateful migration
> from development/beta identities before release.
>
> **Amended 2026-09-21 (pre-release reopening + complete debt audit):** E22 and
> E23 are bounded final capability epics; the old `MacDown 2` public-identity
> freeze is reopened because the release will be a new editor descended from
> MacDown; #115 is a hard gate that closes every historical carried-forward
> requirement/evidence gap before the final E16 freeze and E17 production RC.
> The audit searched closed issues, binding implementation docs, all merged PR
> descriptions, the release ledger, issue-57 findings, and current residual
> source seams; #53/#79/#88/#116-#121 are the named closure records.

---

## 1. Vision

A fast, native, workspace-style Markdown, code and technical-writing editor for
macOS 26 "Tahoe": Swift 6 + SwiftUI, Liquid Glass interface, tabbed editing,
collapsible folder browser, per-document content browser (outline), first-class
support for JSON, HTML and other useful text formats, and text-authored math and
technical diagrams that render beautifully without making the durable document
opaque.

The product remains text-first: Markdown/source is the durable, readable,
diffable representation; previews, equations and diagram graphics are derived
outputs.

First-party opening, editing, preview, math, supported diagram rendering and
HTML/PDF export remain local/offline. Normal first-party functionality does not
upload document content to a hosted renderer or service.

## 2. Locked Decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Deployment floor | **macOS 26+ for macOS 1.0** (Xcode 26 SDK, Swift 6, Liquid Glass automatic; no `UIDesignRequiresCompatibility`) |
| D2 | Tab model | **Native `NSWindow` tabs** — one window = one document, grouped by AppKit tab groups; `WindowCoordinator` owns the pool, each window hosts its own `WorkspaceModel` + sidebar. The mid-point review proved native tabbing composes correctly with the per-window sidebar and provides dedupe, dirty-close and session restore with less custom UI. |
| D3 | Editor | **Custom NSTextView + TextKit 2** wrapped in `NSViewRepresentable`, **tree-sitter** highlighting. Priority: fastest, smoothest experience. |
| D4 | Markdown preview | **Native SwiftUI via Textual** for ordinary Markdown (no WKWebView for Markdown). First-party derived content uses explicit contribution/renderer seams rather than turning Markdown preview into a web page. |
| D5 | Identity | **New product descended from MacDown.** Historical development identity: `MacDown 2` / `com.joncallim.macdown2` (app bundle ID `com.joncallim.MacDown2`, CLI `macdown2`). That identity was provisionally frozen at the 2026-09-19 feature-complete gate, then **explicitly reopened by the owner on 2026-09-21** after deciding the public product should have its own name rather than ship as “MacDown 2”. The final public name, app/bundle/update identity, CLI public name, repository/public links and migration namespaces are re-frozen before E23 commits final Quick Look/theme/document-icon identifiers. E17 must migrate representative development/beta state from the historical MacDown 2 namespaces into that final identity and prove idempotence; it may not decide the brand itself. The public Markdown document UTI remains `net.daringfireball.markdown` unless a later exact integration need justifies additional declarations. **Final identity inputs decided by the owner on 2026-09-28** (`planning/RELEASE_PATH.md` §4): name MostlyText, repository `Joncallim/mostlytext`, bundle ID `app.mostlytext.MostlyText`, CLI `mostlytext`, version 1.0.0 with independent build numbers that only increase, MIT licence, and a signed, notarised DMG on GitHub Releases with `mostlytext.app` as the download site. #158 applies them after E22. |
| D6 | Contributions/extensions | macOS 1.0: internal **renderer-neutral first-party contribution infrastructure** + user local text-filter commands. E12 owns export destination composition; E14 owns the contribution lifecycle/isolation/result seam; E19 owns production math; E20 owns diagram platform + Mermaid; E21 evaluates additional renderers. Post-1.0: evaluate JavaScriptCore extension API. **Never** resurrect NSBundle in-process loading. |
| D7 | Sandboxing | **Unsandboxed** for now (direct distribution). `FileTreeModel` remains security-scoped-ready so later sandboxing is additive. |
| D8 | iPad sequencing | **No iPad implementation before the completed macOS 1.0 release.** Do not add UIKit targets or speculative portability layers during the Mac roadmap. Avoid gratuitous AppKit coupling where platform-neutral engine code is equally simple; actual porting is post-release work. |
| D9 | Local/offline first-party behaviour | Opening/editing/saving, Markdown preview, first-party math, supported first-party diagrams and export require no network connection and do not transmit document content externally. A network-backed document feature requires a later explicit product/security decision; it cannot appear as an implementation shortcut. |
| D10 | Durable text fidelity | Authored text/source is authoritative. Derived caches are disposable. Opening/saving must not gratuitously rewrite encoding, BOM, line endings, final-newline state or unrelated source; deliberate conversions must be explicit and tested. |

## 3. Product Shape

```text
┌────────────────────────────────────────────────────────────────┐
│ Native NSWindow tab bar (AppKit: title / dirty dot / reorder)  │
├────────────────────────────────────────────────────────────────┤
│ Toolbar (glass)                              [sidebar toggle]  │
├──────────────┬──────────────────────────────┬──────────────────┤
│ SIDEBAR      │                              │                  │
│ (collapsible,│  Editor                      │  Preview         │
│  per window) │  NSTextView + TextKit 2      │  Textual (MD)    │
│              │  + tree-sitter highlight     │  + math/diagrams │
│ ▾ FOLDER     │                              │  WKWebView(HTML) │
│   browser    │                              │  Outline (JSON)  │
│ ──────────── │                              │                  │
│ ▾ CONTENT    │                              │                  │
│   browser    │                              │                  │
└──────────────┴──────────────────────────────┴──────────────────┘
```

- **Scene model (as built):** `AppDelegate` + `WindowCoordinator` own a pool of
  `NSWindowController`s — one window per document, grouped as native tabs. The
  SwiftUI `WindowGroup` scene exists only to host the command/menu structure.
  Each window hosts its own `WorkspaceModel`; `TabStore` survives as the
  per-window single-document holder and session-restore seam. **Not**
  `DocumentGroup`.
- **Document lifecycle is re-implemented** (no NSDocument): autosave-on-edit,
  dirty tracking, close-dirty prompts, session restore and external-file
  reconciliation. This is a deliberate trade and remains a data-loss-sensitive
  subsystem (E01/E03/E18).
- **Technical content is derived:** equations and diagrams retain text source in
  the document. Rendered artefacts are cacheable/disposable and never become the
  only copy of user-authored content.
- **Preview and export share derived-content contracts:** contribution/render
  results are renderer-neutral; Preview and Export adapt them for their own
  destinations rather than asking each feature to implement two renderers.

## 4. Module Map (SwiftPM targets)

| Target | Responsibility | Replaces (ObjC) |
|---|---|---|
| `App` | `@main`, `WindowGroup`, commands, menus | MPMainController, MainMenu.xib |
| `Workspace` | WorkspaceModel, TabStore, session restore | — (new) |
| `FileCore` | FileStore (open/save/autosave), FileFormat registry, document lifecycle | MPDocument IO parts |
| `FileTree` | Folder browser model: lazy loading, FS watching, CRUD | — (new) |
| `EditorCore` | NSTextView + TextKit 2 representable, viewport layout, assists | MPEditorView, NSTextView+Autocomplete |
| `Highlighting` | SwiftTreeSitter engine, grammar registry, theme engine | peg-markdown-highlight |
| `MarkdownEngine` | swift-markdown parse pipeline, front matter, source-range index | MPRenderer, Hoedown, LibYAML |
| `Preview` | Format router: MD→Textual + derived-content adapter, HTML→WKWebView, JSON→outline; scroll sync | WebView/templates |
| `OutlineUI` | Content browser (heading tree of active doc) | — (new) |
| `ExportService` | HTML/PDF composition, templates/assets, derived-content export destination | MPAsset/legacy export |
| `AppSettings` | Settings scene + typed storage model | PAPreferences/MASPreferences |
| contribution layer (E14 architecture decides final target name) | renderer-neutral first-party contribution lifecycle/result seam + local text-filter commands | MPPlugIn (retired) |
| `CLITool` | swift-argument-parser launcher | macdown-cmd, GBCli |
| `Themes` | editor/preview themes | Resources/*.styles, *.css |

Do not create a new SwiftPM target merely because the roadmap names a conceptual
area. Each epic architecture pass must justify module changes against live
`master`.

## 5. Technology Selections

Selections below remain subject to re-verification by the owning epic where the
ecosystem/runtime has changed.

| Concern | Choice | Notes |
|---|---|---|
| Markdown AST | `swiftlang/swift-markdown` 0.8.x | cmark-gfm based; source ranges retained |
| cmark HTML (export) | `swiftlang/swift-cmark` 0.8.x | GFM-faithful HTML path |
| MD preview | `gonzalezreal/textual` 0.5.x | Pre-1.0: pin/wrap behind internal seam |
| Editor highlighting | `ChimeHQ/SwiftTreeSitter` + tree-sitter grammars | Incremental highlighting |
| Attr-string fallback | HighlighterSwift | Fallback only |
| YAML front matter | `jpsim/Yams` | Replaces legacy LibYAML path |
| CLI | `apple/swift-argument-parser` | Replaces GBCli |
| Updates | Sparkle 2.x (EdDSA) | New release/update identity |
| Localization | String Catalogs + Transifex | Priority locales first |
| CI | GitHub Actions, macOS 26 environment where available | Real UI execution may require a recorded local-Mac release gate |
| Math renderer | **Not preselected** | E19 verifies capability/licensing/accessibility/offline/export/performance fit |
| Diagram renderers | Mermaid + D2 + Graphviz/DOT ship for macOS 1.0; WaveDrom rejected for 1.0 after E21/#115 security review | All shipped renderers remain local/offline; future WaveDrom reconsideration requires a materially safer integration path |

**Dependency policy:** prefer/require SwiftPM for Swift package dependencies,
pin exact versions where practical, and wrap third-party UI/runtime dependencies
behind narrow internal protocols. Do not bundle a large runtime or add a hosted
service merely to satisfy a roadmap noun; the owning architecture must justify
security, licensing, bundle size, offline behaviour, maintenance and product
value.

## 6. Epic Roadmap

### Milestones / phases

| Milestone/phase | Goal | Epics |
|---|---|---|
| **M1 — Skeleton** | App launches, opens/saves files in tabs | E00, E01, E02, E03 |
| **M2 — Editor** | World-class text editing + highlighting | E04, E05, E10 |
| **M3 — Markdown core** | Live native preview + content browser | E06, E07, E08 |
| **M4 — Workspace & formats** | Folder browser, JSON/HTML/TeX source, export, settings, live external files | E09, E11, E12, E13, E18 |
| **M5A — Feature completion** | Safe contribution seam + first-class technical writing | E14, E19, E20, E21 |
| **Feature-complete gate** | Prove the original Mac product surface and establish the release-evidence baseline | all major original macOS 1.0 features through E21 + release-hardening evidence |
| **M5B — Polish & pre-release completion** | E15 whole-app/first-run → E16 translation baseline → E22 editor essentials → public identity re-freeze → E23 themes/Quick Look/Finder polish → #115 closed-epic debt closure → final E16 string freeze → E17 distribution | E15, E16, E22, E23, #115 gate, E17 |
| **Post-1.0** | Evaluate/implement iPad from a finished Mac product | future work only after E17 release gate |

GitHub's existing `M5 — Polish & ship` milestone may continue to hold E14-E23
administratively; this document defines the logical ordering inside M5. E23 is the final planned capability epic; work after it is release evidence, localisation re-freeze and distribution rather than another feature wave.

### Dependency graph

```text
E00 ─▶ E01 ─▶ E02 ─▶ E03 ─▶ E09
  │      │
  │      ├─▶ E04 ─▶ E05 ─▶ E10
  │      │
  │      └─▶ E06 ─▶ E07 ─▶ E08
  │                   │
  │                   ├─▶ E11 ─▶ E12 ─┐
  │                   │                 ├─▶ E19 ─┐
  │                   └────────▶ E14 ──┤       │
  │                                     └─▶ E20 ─▶ E21
  │
  └────────────────────▶ E13

E18: E01 + E03(as built) + E04; completed implementation, evidence carried into release ledger

E19 + E21 + remaining original Mac features
  ─▶ FEATURE-COMPLETE GATE
  ─▶ E15 (whole-app + first-run/in-app copy)
  ─▶ E16 (translation infrastructure/current baseline)
  ─▶ E22 (editor essentials)
  ─▶ FINAL PUBLIC IDENTITY RE-FREEZE
  ─▶ E23 (themes + Markdown Quick Look + Finder polish; final capability epic)
  ─▶ #115 CLOSED-EPIC DEBT CLOSURE GATE
  ─▶ E16 FINAL LOCALISATION/STRING FREEZE
  ─▶ E17 (identity/state migration + signed/updateable macOS 1.0 release)
  ─▶ only then post-1.0 iPad work
```

Each architecture pass recalculates actual dependencies from live repository
state rather than treating this diagram as a substitute for inspection.

## 7. Repository, epic and branch strategy

- The rewrite lives on **`master`** of `Joncallim/macdown_2`; the legacy ObjC app
  survives only as read-only porting source in `legacy-reference/`.
- One branch per epic: `epic/NN-short-name` → PR into `master`.
- Every new/materially revised epic follows `planning/EPIC_STANDARD.md`:
  - live GitHub issue = product contract;
  - current-master `planning/epic-NN-implementation.md` = binding engineering contract;
  - dependency-ordered slices = worker execution contracts.
- Every remaining macOS 1.0 epic also reconciles applicable
  `planning/RELEASE_HARDENING.md` rules.
- Older architecture work is not automatically binding after its product or
  release contract changes; it must be refreshed before implementation.
- Broad implementation begins only after Definition of Ready.
- PR merge requires CI/tests **and** applicable Definition of Done evidence;
  green CI alone is not proof of user-facing correctness.
- Durable decisions discovered in PR/review work are reconciled into repository
  documentation; they do not live only in an agent conversation.
- Workers stop/escalate when a false assumption requires unauthorised
  architecture, a new cross-module dependency, changed product behaviour,
  weakened tests or edits outside agreed ownership.

### Human-readable history rule

Repository history is written for people first.

- Commit subjects describe the outcome in plain English. Epic/slice IDs are
  traceability, not descriptions.
- PRs begin with what changes, why, how it works in ordinary language, what the
  owner should test, risks/limits and verification evidence.
- Architecture documents begin with an owner summary before symbols/data flow.
- Define non-obvious jargon; do not depend on an agent conversation to make a
  document meaningful.
- Avoid unexplained shorthand such as `E20 S3`, `wire seam`, `tail`, `plumbing`,
  `follow-up` or `agent changes` as the sole explanation.

Detailed rules live in `planning/EPIC_STANDARD.md`,
`planning/RELEASE_HARDENING.md` and the GitHub PR/epic templates.

## 8. Performance Budgets

| Metric | Budget | Verified in |
|---|---|---|
| Cold launch → interactive | < 1 s (M-series) | E00, re-checked E15 |
| Open 1 MB .md → text visible | < 300 ms | E04 perf test |
| Open 1 MB .md → fully highlighted | < 500 ms | E05 perf test |
| Keystroke → highlight update | < 50 ms | E05 perf test |
| Keystroke → preview refresh (debounced) | < 150 ms | E07 perf test |
| Folder with 10k entries → expand | < 200 ms | E09 perf test |
| Memory, 20 typical tabs | < 300 MB | E15 audit |
| Math/diagram rendering | epic-specific budgets required | E19-E21 Release/integration evidence |

> **Measurement caveat (#28):** some existing budgets were initially verified
> as package-level benchmarks rather than complete application-path
> measurements. The full path — NSTextView edit → model publication →
> highlighting/preview/derived-content refresh — must be measured where a
> product claim depends on it. README/release claims cannot exceed the layer
> actually measured.

E19-E21 explicitly separate cache/unit benchmarks from real Release-app editing
responsiveness in mixed technical documents.

## 9. Testing and evidence strategy

- **Framework:** Swift Testing for new package code; preserve existing XCTest/
  XCUITest where app/UI testing requires it.
- **Coverage per epic:** every acceptance criterion maps to named evidence in
  the implementation architecture.
- **Critical UI execution:** XCUITests that prove release-blocking app behaviour
  must actually run on macOS 26 before 1.0. `build-for-testing` alone is not a
  pass. If hosted CI cannot execute them, record a repeatable local-Mac command
  and result; unavailable rows are `unverified`, never inferred green.
- **Release-evidence ledger:** feature-complete gate records implementation,
  automated evidence, real-app/Release evidence, manual evidence, open
  P0/P1/P2 and release status for every major capability.
- **Fidelity corpus:** real-world Markdown/export corpus in E12, extended by E19
  for math and E20/E21 for diagrams.
- **Text round-trip corpus:** encodings, relevant BOM cases, LF/CRLF,
  Unicode/emoji/CJK, final-newline state, no-op open/save, large files, Save As
  and external atomic rewrites. No unexplained normalisation is accepted.
- **Adversarial corpus:** malformed, oversized, rapid-change, dependency-failure
  and renderer-failure cases planned before technical-content epics close.
- **Release dogfooding:** perceived responsiveness and complete user journeys
  are checked in Release builds, not inferred from Debug feel.
- **Environment note:** authoritative app builds/tests require a Mac with Xcode
  26; hosted CI limitations are evidence limitations, not proof of success.

## 10. Risk Register

| Risk | Mitigation |
|---|---|
| Hand-rolled document lifecycle → data-loss bugs | explicit state machine + E01/E03/E18 regression/UI tests + recovery buffer + release destructive-path dogfood |
| Textual pre-1.0 API churn | pin version; preview seam; WKWebView remains scoped to HTML |
| SwiftTreeSitter grammar packaging friction | grammar registry isolates additions; add languages deliberately with tests |
| Whole-document parse/model publication cost | measure complete path; optimise measured bottlenecks; never market package benchmarks as app-path proof |
| Tab/session restore edge cases | best-effort restore; corrupted-state and release-ledger coverage |
| Math/diagram runtime complexity | E12/E14 shared derived-content contract; E19/E20 verify one capability at a time; E21 admits candidates individually |
| Renderer security/licensing/bundle surprises | local/offline admission gate; candidate can be rejected without blocking E21 |
| Text-filter command abuse/hangs | structured process launch; bounded time/stdout/stderr; cancellation; failure preserves original text; no shell interpolation |
| Silent file normalisation | D10 + feature-complete text round-trip fidelity corpus |
| Closed-issue evidence debt forgotten | owner-readable release-evidence ledger; closed != release-proven |
| UI tests only compile, never run | critical UI execution required on a real/suitable macOS 26 environment |
| Identity chosen too late | feature-complete gate freezes public identity before E15 icon/first-run and E16 localisation |
| Development→release state loss | E17 stateful identity/update migration rehearsal with sessions/settings/recovery data |
| Post-localisation UI churn | E15 finalises in-app first-run/copy; E16 string freeze; E17 new app strings require localisation re-verification |
| Feature creep before release | E21 is final planned major macOS 1.0 feature work; release hardening adds gates, not features |
| Premature multi-platform work | D8 forbids iPad implementation before macOS 1.0 |
| Opaque agent-generated history | EPIC_STANDARD + templates + owner-first documentation/commit rules |

## 11. Release Strategy

- `MacDown 2` is the development identity only. On 2026-09-21 the owner
  explicitly chose to ship a **new editor descended from MacDown**, so the
  earlier public-identity freeze is reopened in a controlled way.
- Private alpha/dogfooding continues throughout pre-release completion; closing
  an implementation epic does not erase outstanding release evidence.
- The 2026-09-19 feature-complete gate remains valid as the evidence baseline
  for the original E00-E21 surface; E22/E23 do not retroactively claim that
  evidence covers their new behaviour.
- E15 remains the whole-app/accessibility/first-run baseline. E22/E23 rerun the
  affected portions rather than repeating unrelated evidence.
- E16's current catalogs/translations are a valid localisation baseline, but
  its **final** string freeze is intentionally deferred until E22 and E23 have
  landed and their UI/string deltas have been translated and pseudo-localised.
- E22 adds the bounded day-to-day editor essentials already approved in issue
  #112. E23 adds themes, Markdown Quick Look and Finder integration and is the
  **last planned macOS 1.0 capability epic**.
- The final public product name/bundle/update/CLI strategy is re-frozen before
  E23 commits final extension/theme-file/document-icon identifiers.
- After E23, no further capability work enters 1.0 unless release testing proves
  an ordinary workflow is broken. Issue #115 then closes every historical
  carried-forward/residual/unverified item from closed epics: each must be fixed,
  proved on a suitable environment, or explicitly rejected only where the original
  candidate contract allowed rejection. Only after #115 closes does E16 perform
  the final localisation/string-freeze delta and E17 package the app.
- E17 rehearses migration of representative development/beta state into the
  final identity, signs/notarises, verifies Sparkle updates and publishes macOS
  1.0. It does not invent new user-facing release UI after the final string freeze.
- No release-relevant P0/P1/P2 remains for macOS 1.0 after #115; cosmetic P3s require explicit owner acceptance.
- iPad implementation begins only after the completed E17 release.
- Legacy MacDown remains available; no forced migration.

## 12. Open Decisions

| # | Question | Blocks |
|---|----------|--------|
| O1 | **Partially resolved 2026-09-25:** the owner has settled the public product name as **MostlyText**, with domains `mostlytext.app` and `mostlytext.dev` owned (not `mostlytext.org`). This settles the *name* only — domain ownership does not by itself establish the bundle ID, signing identity, appcast URL, DNS configuration, or approved artwork/icon, all of which remain concrete inputs to prepare once (not to reopen) before E23 commits final identifiers. CLI public name, repository/public-link strategy, and the development→release namespace migration plan (E17) are still open. | **E23 final identifiers / final E16 freeze / E17** |
| O2 | Where does the app live long-term: rename this fork, or fresh repo? | Public identity re-freeze before E23 final identifiers |
| O3 | Import old MacDown prefs/themes on first run? | E13; if approved, must be stable before E15/E16 first-run/string freeze |
| O4 | **Resolved 2026-09-21:** E23 expands to at least 8 deliberate bundled themes (>=4 light, >=4 dark) plus safe declarative custom themes; provenance/licensing and contrast are release gates. | E23 |
| O5 | Final math rendering engine and exact delimiter compatibility | E19 architecture |
| O6 | **Resolved:** Mermaid, D2 and Graphviz/DOT ship; WaveDrom is rejected for macOS 1.0 after the #115 final disposition (unsafe documented `eval()` path; safe parser work not justified for 1.0). | — |

## 13. Appendix — D6: Contribution and extension design

**Old system (retired):** `MPPlugIn` loads NSBundle code in-process and injects
JavaScript into a preview WebView. Arbitrary in-process loading is a
stability/security dead end and is not carried over.

**New model, layered:**

1. **macOS 1.0 — Export destination seam (E12).** Ordinary Markdown HTML/PDF
   composition plus a narrow destination contract that later first-party
   derived content can feed without creating another export pipeline.
2. **macOS 1.0 — First-party contribution seam (E14).** Renderer-neutral source
   identity + derived representation + diagnostics + lifecycle/isolation. Preview
   and Export adapt the same result. TOC/test contribution prove the seam; E14
   does not claim production math or Mermaid.
3. **macOS 1.0 — Local text-filter commands (E14).** Executable scripts consume
   selection/document input and return a replacement only on successful bounded
   execution. Structured launch, explicit working directory/environment,
   timeout/cancellation, bounded stdout/stderr and source-preserving failure are
   mandatory.
4. **macOS 1.0 — First-party technical content.** E19 uses the contribution model
   for math. E20 establishes the diagram renderer platform and Mermaid. E21
   evaluates D2, Graphviz/DOT and WaveDrom individually and ships only accepted
   candidates.
5. **Post-1.0 — JavaScriptCore extensions (evaluate).** Possible sandboxed hooks
   or custom fenced-block renderers/commands; third-party loading is not a 1.0
   requirement.
6. **Later — ExtensionKit out-of-process extensions (evaluate only if demanded).**

The contribution layer remains narrower than a generic plugin framework.
First-party technical-content work may extend it only when a concrete product
requirement demonstrates the need.

## 14. Post-1.0 iPad strategy

The iPad port is deliberately **not part of the macOS completion roadmap**.
The product first proves that its document model, editor, preview, math,
diagrams, export, fidelity, recovery and update behaviour form a complete Mac
application.

After macOS 1.0 ships, future work may:

1. identify which MacDownKit modules are genuinely platform-neutral and isolate
   AppKit-only adapters where required by a real iPad target;
2. build an iPad document/editor shell using appropriate UIKit/SwiftUI document
   APIs and TextKit host;
3. bring preview, math, diagrams, themes and source navigation to iPad;
4. add iPad-specific file/workspace, multiwindow, keyboard and touch behaviour;
5. run an iPad-specific accessibility/performance/release pass.

Do not pre-build those layers during macOS work. The only current constraint is
to avoid needless AppKit dependencies in engine code when a platform-neutral
implementation is equally clear and no more abstract.

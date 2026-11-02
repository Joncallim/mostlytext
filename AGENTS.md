# AGENTS.md

## What this repo is

Fork of MacDown hosting the **MacDown 2** rewrite (Swift 6 / SwiftUI,
macOS 26+). The rewrite lives on `master`; the legacy ObjC app survives only
as a read-only porting source in `legacy-reference/`.

## Layout

- `legacy-reference/` — legacy ObjC tree (themes, `MPColor`/`MPUtilities`
  tests, resources). Porting source only. Do not modify.
- `MacDown2/` — the new product.
  - `MacDown2/MacDown2/` — app target sources
  - `MacDown2/MacDown2CLI/` — CLI target sources
  - `MacDown2/Packages/MacDownKit/` — SPM modules (see `planning/MIGRATION_PLAN.md` §4)
  - `MacDown2/project.yml` — XcodeGen spec (regenerate; never hand-edit the xcodeproj)
- `planning/` — migration plan + epic definitions; epics are tracked as issues on
  `Joncallim/macdown_2` (milestones M1–M5).
- `planning/EPIC_STANDARD.md` — mandatory Definition of Ready, architecture,
  slice, Definition of Done, and human-readability rules for new epic work.
- `planning/RELEASE_HARDENING.md` — binding cross-epic macOS 1.0 integration,
  identity, evidence, offline/privacy, fidelity, localisation and release gates.
- `planning/RELEASE_PATH.md` — coordination map from current `master` to public
  MostlyText 1.0: order, cloud/Mac split, open owner decisions. Adds no scope.
- `design/` — MostlyText design packet (`DESIGN_CONTEXT.md`, `DECISIONS.md`)
  and the canonical brand assets.
- `compliance/` — third-party licence/provenance gate (#148): `inventory.json`,
  generated notices and SBOM, and `tools/compliance.py`. Update the inventory in
  the same change as any new dependency or bundled file.
- `website/` — draft of the `mostlytext.app` download site. Not deployed before
  E17; see its claims ledger.

## Commands (from repo root)

| Task | Command |
|---|---|
| Generate Xcode project | `cd MacDown2 && xcodegen generate` |
| Build app | `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build` |
| Build CLI | `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MostlyTextCLI -destination 'platform=macOS' build` (the executable is `mostlytext`) |
| Build app for dogfooding | `MacDown2/scripts/pin-xcode-package-versions.sh`, then the command above + `-configuration Release -onlyUsePackageVersionsFromResolvedFile` — Debug Swift has no optimizations and materially changes how the app feels to type in; judge responsiveness on a Release build, not Debug |
| Pin Xcode to locked dependency versions | `MacDown2/scripts/pin-xcode-package-versions.sh` after `xcodegen generate`, then add `-onlyUsePackageVersionsFromResolvedFile` to `xcodebuild`. CI does this for every Xcode build; the plain "Build app" command above does not, so Xcode resolves on its own |
| Build + test package | `cd MacDown2/Packages/MacDownKit && swift build && swift test` (CI adds `--force-resolved-versions`) |
| Lint | `swiftlint lint --strict MacDown2` |
| Format check | `swiftformat --lint MacDown2` |

## Rules

- macOS 26.0 only; no availability checks.
- Swift 6 + strict concurrency; warnings are fixed, not ignored.
- SPM only; third-party deps pinned and wrapped behind internal protocols
  (see `planning/MIGRATION_PLAN.md` §5).
- `MacDown2/Packages/MacDownKit/Package.resolved` is committed and is the
  dependency lock. CI enforces it for the package build/tests and every Xcode
  build; locally it is enforced only with `--force-resolved-versions` or the
  pin step + flag above. Change it only in a deliberate dependency update
  (`swift package update` or `resolve`), reviewed like any other code.
- One branch per epic (`epic/NN-name`) → PR into `master`.
- Before starting or materially revising an epic, read and follow
  `planning/EPIC_STANDARD.md`.
- For any remaining macOS 1.0 epic or release-gate work, also read and reconcile
  `planning/RELEASE_HARDENING.md`. An older architecture document is not
  grandfathered in when the product/release contract has changed.
- An epic must satisfy the Definition of Ready before broad implementation
  begins. The implementation architecture is written from the current live
  `master` state, not copied blindly from an older issue.
- The implementation architecture is binding for the epic branch. Workers may
  make ordinary local coding decisions, but must stop when a false assumption
  would require new architecture, a new cross-module dependency, changed
  product behaviour, weakened tests, or edits outside the authorised area.
- CI green + tests included + epic issue referenced are required for a PR, but
  they are not by themselves the Definition of Done. Release-build evidence,
  required dogfood paths, documentation reconciliation and residual risks must
  also be recorded where applicable.
- First-party opening/editing/preview/math/diagram/export functionality is local
  and offline by default. Do not introduce a hosted renderer or transmit
  document content as an implementation shortcut without an explicit new
  product/security decision.
- Tabs are **native `NSWindow` tabs** (as-built E03): one window = one
  document; `WindowCoordinator` owns the pool. Do not reintroduce an in-app
  tab bar.
- Tests use Swift Testing (`@Test`), not XCTest, for all new package code.
- iPad implementation is explicitly post-macOS-1.0 work. Do not add iPad
  targets, UIKit shells or speculative portability layers before the Mac app is
  feature-complete and released. New engine-level code should avoid gratuitous
  AppKit coupling when a platform-neutral design is equally simple, but do not
  add abstraction solely for a future iPad port.

## Human-readable repository history

The repository must be understandable without access to the chat, prompt or
agent session that produced a change.

- Commit subjects describe the actual outcome in plain English. Epic/slice IDs
  may be appended for traceability but cannot replace the description.
- Avoid agent shorthand such as `E20 S3`, `wire seam`, `follow-up`, `agent
  changes`, or `WIP` as standalone commit subjects.
- When a commit's reason is not obvious, include short `What`, `Why`, and
  `Verification` paragraphs in the commit body.
- PR descriptions lead with: **What this changes**, **Why**, **How it works**,
  **What I should test**, **Risks and limits**, and **Verification**. Technical
  symbol-level detail comes after the human summary.
- Architecture documents begin with an owner summary that states the user
  outcome, rationale, main approach, risks and non-goals in ordinary language.
- Define non-obvious abbreviations and specialised terms on first use.
- Comments and documentation explain durable behaviour and rationale, not the
  temporary orchestration process used to generate the code.

If the owner cannot understand what changed, why it was chosen, what could go
wrong and how to test it without reading the implementation diff, the
communication is not complete.

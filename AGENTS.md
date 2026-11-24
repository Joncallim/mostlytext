# AGENTS.md

## What this repo is

**MostlyText**, the native macOS text and Markdown editor (Swift 6 / SwiftUI,
macOS 26+), lives in `Joncallim/mostlytext` on `main`. Its complete MacDown 2
development history is preserved. Original MacDown source/history is frozen at
read-only reference tag `macdown-original-reference-3e2a2bf1`, separately from the
rewrite branch. There is no `legacy-reference/` directory in the current tree.

The website is a separate repository, `Joncallim/mostlytext-site`, with its own
licence. The engineering backlog has moved to
`https://github.com/Joncallim/mostlytext/issues`. Use the new numbers for new work;
[the transfer map](planning/ISSUE_TRANSFER_MAP.md) resolves imported bare issue
numbers to their current issues. Historical closed issues, PRs, alpha releases
and workflow evidence remain in `Joncallim/macdown_2`. Never mass-renumber those
records or retarget exact-source/native receipts.
See `planning/downstream/mostlytext-brand-backlog-cutover-2026-11-03.md`.

## Layout

- `macdown-original-reference-3e2a2bf1` — historical original MacDown Git tag,
  not a current directory or runtime dependency. Treat reference source as read-only.
- `MacDown2/` — the new product.
  - `MacDown2/MacDown2/` — app target sources
  - `MacDown2/MacDown2CLI/` — CLI target sources
  - `MacDown2/Packages/MacDownKit/` — SPM modules (see `planning/MIGRATION_PLAN.md` §4)
  - `MacDown2/project.yml` — XcodeGen spec (regenerate; never hand-edit the xcodeproj)
- `planning/` — migration plan + epic definitions; epics are tracked as issues on
  `Joncallim/mostlytext` (historical IDs resolve through the transfer map).
- `planning/EPIC_STANDARD.md` — mandatory Definition of Ready, architecture,
  slice, Definition of Done, and human-readability rules for new epic work.
- `planning/RELEASE_HARDENING.md` — binding cross-epic macOS 1.0 integration,
  identity, evidence, offline/privacy, fidelity, localisation and release gates.
- `planning/ACCEPTANCE_STATUS.md` — dated current acceptance/prerequisite results;
  `planning/IDENTITY.md` — current names, implemented types and reserved handoff.
- `planning/RELEASE_PATH.md` — coordination map from current `main` to public
  MostlyText 1.0: order, cloud/Mac split, open owner decisions. Adds no scope.
- `design/` — MostlyText design packet (`DESIGN_CONTEXT.md`, `DECISIONS.md`)
  and the canonical brand assets.
- `compliance/` — third-party licence/provenance gate (MostlyText #14, formerly #148): `inventory.json`,
  generated notices and SBOM, and `tools/compliance.py`. Update the inventory in
  the same change as any new dependency or bundled file.
- `website/` — retained download-site draft/history. Current website source is
  `Joncallim/mostlytext-site`; follow that repository for site edits. Publication
  remains an E17 gate; this snapshot is not a deployment.

## Commands (from repo root)

| Task | Command |
|---|---|
| Generate Xcode project | `cd MacDown2 && xcodegen generate` |
| Build app | `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build` |
| Build CLI | `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MostlyTextCLI -destination 'platform=macOS' build` (the executable is `mostlytext`) |
| Build app for dogfooding | `MacDown2/scripts/pin-xcode-package-versions.sh`, then the command above + `-configuration Release -onlyUsePackageVersionsFromResolvedFile` — Debug Swift has no optimizations and materially changes how the app feels to type in; judge responsiveness on a Release build, not Debug |
| Pin Xcode to locked dependency versions | `MacDown2/scripts/pin-xcode-package-versions.sh` after `xcodegen generate`, then add `-onlyUsePackageVersionsFromResolvedFile` to `xcodebuild`. CI does this for every Xcode build; the plain "Build app" command above does not, so Xcode resolves on its own |
| Test affected package suite | `cd MacDown2/Packages/MacDownKit && swift test --force-resolved-versions --filter '<SuiteOrTest>'` |
| Test full package | `cd MacDown2/Packages/MacDownKit && swift test --force-resolved-versions` |
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
- One branch per epic (`epic/NN-name`) → PR into `main`.
- Before starting or materially revising an epic, read and follow
  `planning/EPIC_STANDARD.md`.
- For any remaining macOS 1.0 epic or release-gate work, also read and reconcile
  `planning/RELEASE_HARDENING.md`. An older architecture document is not
  grandfathered in when the product/release contract has changed.
- An epic must satisfy the Definition of Ready before broad implementation
  begins. The implementation architecture is written from the current live
  `main` state, not copied blindly from an older issue.
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

## Lean testing and review

These rules govern iteration, not acceptance. [Release Hardening §12](planning/RELEASE_HARDENING.md#12-test-evidence-and-flakiness-policy), required CI, and the [release sequence](planning/RELEASE_SEQUENCE.md) remain binding.

- **Start at the smallest owning boundary.** Inspect the diff and its direct
  consumers. Run the failing case or affected suite first, then show
  fail-before/pass-after on a deterministic reproducer for fixes. Prefer a tiny,
  intentional fixture, fixed inputs, and explicit async completion to sleeps
  or large incidental fixtures. Extend a nearby test before adding another;
  add a second layer only if it proves a different failure mode. Keep the
  workload necessary to establish a real performance or renderer failure.
- **Pick the right lane.** Pure Swift package changes start with the narrow
  owning Swift Testing suite and the committed lock. App-only changes start
  with the relevant `MacDown2Tests` case or suite; preserve the pinned Xcode
  build and serial test options. Test cross-boundary changes where the app,
  CLI, WebKit, renderer or export actually consumes the result. Use actual
  macOS 26 UI execution when window, input, file, or accessibility behavior is
  under test; compilation is not execution. Use an optimized Release build for
  responsiveness conclusions; do not repeat Debug and Release by habit, or
  omit either when behavior differs or the gate requires both.
- **Broaden before merge where impact spreads.** Use the existing
  [CI selector](.github/scripts/select-ci-tests.py) as a conservative guide to
  affected package targets and reviewed app suites; do not build a second
  matrix or treat its output as acceptance. Cover downstream consumers for
  shared interfaces or uncertain impact. Changes to manifests, pins, bundled
  resources, generated project inputs, or CI selection call for broader checks
  as applicable. Run the existing required workflow checks on the actual final
  head; retain explicit full integration/release runs where required.
- **Avoid duplicated setup and repairs.** Prefer incremental builds and reuse
  a compatible build/fixture on the same revision, configuration, toolchain
  and dependency lock; `swift test` already builds the tests. Generate and pin
  the Xcode project once per unchanged input set. Isolate writable worktrees,
  scratch/DerivedData, GUI profiles and evidence directories by agent; keep
  load-sensitive app/UI lanes serial on the same Mac. Do not replace evidence
  for the current candidate with a cached result from different inputs.
- **Review in bounded tranches.** Within the existing epic branch convention,
  group related fixes serving one acceptance outcome, not unrelated edits or
  one PR per test. Carry exact, still-applicable evidence forward with its
  revision, scope and configuration. Request targeted independent re-review for
  changed boundaries and the integrated/cold review at the required gate; do
  not repeat a full panel against unchanged work. Record first failures before
  diagnostic retries and keep intermittency visible as required by §12.
- **Keep routine reports short.** Give the tested revision, command/scope,
  result, tests not run and why, plus the next real gate; link logs and evidence
  instead of copying them. Docs-only changes need link, accuracy and diff
  checks, not runtime tests unless the modified docs are bundled or otherwise
  consumed. Never weaken required final-head CI, repeated full release-suite
  runs, actual native/signed artifact checks, rights/compliance, or release and
  publication approvals. A scoped pass is not a release pass.

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

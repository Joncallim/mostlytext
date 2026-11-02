# MostlyText 1.0 release path

## Current coordination checkpoint — 2026-10-29

This dated update supersedes the live-status statements in the October 26
snapshot below; that snapshot is retained as historical evidence, not as a
current work queue. GitHub branch, PR, issue and exact-head check metadata were
read on 2026-10-29. Merge status is not release or native acceptance.

- The current `integration-final` head is
  [`1c773427`](https://github.com/Joncallim/macdown_2/commit/1c773427ae0e4bb934b9d6a0914707ef98a1bfe9).
  [#509](https://github.com/Joncallim/macdown_2/pull/509) merged on October 28,
  followed by [#505](https://github.com/Joncallim/macdown_2/pull/505).
  [#120](https://github.com/Joncallim/macdown_2/issues/120) is closed. The
  historical draft and Trash-hold statements below no longer describe these
  items. Their issue/PR evidence remains authoritative; this document does not
  broaden owner-accepted evidence limitations or claim a published release.
- [#520](https://github.com/Joncallim/macdown_2/pull/520) remains draft at
  `758152ed6638e381704e23af34cc7c067bc92208`.
  [CI 40721494606](https://github.com/Joncallim/macdown_2/actions/runs/40721494606)
  passed build-and-test, but lint was cancelled with no executed steps, so the
  overall run is not green. Compliance passed. Reconcile the current native
  evidence and outstanding check before merge; the October 26 candidate is
  not evidence for this head.
- [#532](https://github.com/Joncallim/macdown_2/pull/532) remains draft at
  `f5605d9aead306e15ccb1bd8fb4f48b8931c1f76`.
  [CI 40322381213](https://github.com/Joncallim/macdown_2/actions/runs/40322381213)
  failed at package build/tests; subsequent app checks did not run. Lint and
  Compliance passed. Its native Release export acceptance remains unverified
  by this checkpoint; the older pending-run description below is historical.
- [#519](https://github.com/Joncallim/macdown_2/pull/519) and
  [#533](https://github.com/Joncallim/macdown_2/pull/533) remain draft at their
  October 26 heads. Their exact-head CI and Compliance passed, but those
  results alone do not establish native permission acceptance or explain the
  historical session-publication failure.
- Release, migration, dependency/pin, signing, website and publication gates
  remain separate. This documentation change waives none of them. Historical
  workflow and credential descriptions below must be reconciled with their
  owning issue and current owner decisions before execution.

## Historical integration checkpoint — 2026-10-26

The order and release gates below remain the coordination contract, but their
2026-09-28 status and credential inventory are historical. This snapshot
records the latest app-code `integration-final` checkpoint as
`d04bca8e93ac34120b7e2e48422d52588a3f50c4` (tree
`d50f19b6d8ce8537a6eccdc0522c0ec984e245b0`). This is an engineering
integration baseline, not a signed release candidate. Its exact-head CI run
`40286608868` and Compliance run `40286608854` passed, including locked
package tests, Debug and Release builds, app-target tests, dependency
verification and lint.

Recent narrow [#183](https://github.com/Joncallim/macdown_2/issues/183)
corrections are integrated:

- [#521](https://github.com/Joncallim/macdown_2/pull/521), merged at
  `b79f8d85e33c176f26c7c0ccf92c097ed1ff6ceb`, binds recovery loading to
  the FileDocument lifetime. Its locked focused FileDocument suite passed
  15/15, independent source review accepted it, and hosted CI run
  `40259974415` passed.
- [#522](https://github.com/Joncallim/macdown_2/pull/522), merged at the
  earlier checkpoint `19b4a5b7`, rejects recovery publication unless the
  proposed text is byte-for-byte identical to the captured session snapshot's
  text. The focused app regression passed 7/7; the combined-head
  FileDocument suite passed 15/15 locally. Independent source and combined-tree
  reviews accepted it,
  and hosted CI run `40262502856` passed.
- [#527](https://github.com/Joncallim/macdown_2/pull/527), merged at
  `b4ff944c`, keeps Save error ownership bound to the original operation.
  Independent source review and exact-head CI run `40268810688` passed; this
  package-level change does not establish native Save UI acceptance.
- [#524](https://github.com/Joncallim/macdown_2/pull/524), merged at
  `b435fd82`, retires Folder Search results when an index refresh fails or
  the active root changes. [#528](https://github.com/Joncallim/macdown_2/pull/528),
  merged at `dc952693`, keeps later row clicks, match reveal and Replace
  inclusion bound to the result the user saw. Their source reviews and
  exact-head CI runs `40272393710` and `40274842156` passed.
- [#529](https://github.com/Joncallim/macdown_2/pull/529), merged by the
  earlier `a129ae2b` checkpoint and retained in current integration, blocks
  stale session publication after a newer edit,
  including a dirty-to-dirty edit that does not schedule a coordinator save.
  Its source review and exact-head CI run `40275023542` passed. Independent
  combined-tree review found no interaction with #528, and the post-merge
  CI at that earlier checkpoint passed on their combined tree.
These results land only the named implementation slices. #183 remains open
pending reconciliation of its other findings and the required real-app
recovery, filesystem, relaunch and Release evidence. Green CI does not replace
the release-evidence ledger or
[#115](https://github.com/Joncallim/macdown_2/issues/115) acceptance.

Separate from #183, [#531](https://github.com/Joncallim/macdown_2/pull/531)
implements the #116 guard for invalid rendered math image dimensions before
HTML width/height conversion. Its independent source review and exact-head CI
run `40282586058` passed; current integration-head CI run `40286608868` also
passed.
This change does not establish a pre-allocation raster memory budget.

## Historical draft and acceptance status — 2026-10-26

- [#532](https://github.com/Joncallim/macdown_2/pull/532) is a draft #117
  slice at `7a9a06c15b04e7ce7e5bf2788da7b8c177c97fbd`. It freezes the accepted
  document text, theme and effective Markdown parse options for both
  contribution parsing and final HTML/PDF composition. Independent source
  review and local format, lint and syntax checks passed. Compliance run
  `40290713699` and lint job in CI run `40290713620` passed; package and app
  checks were still running when this checkpoint was written. Native Release
  panel, PDF and close/cancel acceptance remains outstanding. The PR remains a
  draft.
- [#533](https://github.com/Joncallim/macdown_2/pull/533) records diagnostics
  for the historical #183 dirty-edit session-publication failure. CI run
  `40281269838` failed three final assertions in
  `SessionPublicationDirtyEditTests.swift` at lines 60–62 after the recovery
  buffer contained the second edit. Diagnostic PR head
  `201be73782b3ca75dce936be4e20c01afc7a7ed7` passed its exact-head CI and
  Compliance runs `40286438757` and `40286438651` without reproducing the
  rejection. The later current integration head also passed app-target tests
  in run `40286608868`. The original failure remains unexplained; no production
  retry change or #183 closure is justified by this evidence.
- [#519](https://github.com/Joncallim/macdown_2/pull/519) remains a draft for
  #121 at head `4fbaba397b32980f29ddf9a79ca012c623eeb603`. A temporary combined
  native candidate based on the earlier `a129ae2b` integration passed the
  tested chooser cancel, wrong-folder, valid ancestor-grant, sibling-denial,
  revocation, tab-switch and reselection flows. This does not establish signed
  sandbox permission behavior, and the tested candidate does not include the
  current `d04bca8e` base. Reconcile and rerun on the exact current candidate
  before merge or issue closure.
- [#520](https://github.com/Joncallim/macdown_2/pull/520) remains a draft for
  #112 at head `6238eaa0c9cec87512acf085c5bceae475aeb312`. The same earlier
  combined native candidate passed the observed current-line, gutter,
  multiselection and save/reopen checks, but a 1.15 MB single-paragraph preview
  became unresponsive. A retained sample showed repeated main-thread SwiftUI
  text-layout/Core Text measurement in the one-Text oversize fallback. The
  native task owns that performance investigation; this is not #203 closure or
  proof of release responsiveness. Retest on the exact current integration
  candidate after a reviewed fix.
- [#509](https://github.com/Joncallim/macdown_2/pull/509) remains a draft for
  #112 at head `680812ad07ab727885e8ef3e9bb33ef7983fcf8a`. Its sidebar and
  checked-encoding source changes do not yet have completed native acceptance.
- #505's missing-file recovery test remains held pending its separate Trash
  approval. #53 migration activation remains gated by its compatibility,
  consent and recovery contracts. #203 dependency or pin changes remain held
  for their explicit decision. None of these gates is waived by the results
  above.

**Historical owner summary (2026-09-28).** This is the coordination map from
the recorded `master` baseline to a
public, signed and downloadable MostlyText 1.0. It adds no scope. Every item
below already has an owning issue or epic, and those issues remain the
binding contracts. This page shows:
- the order the work must happen in;
- what can start now;
- which steps need a Mac rather than a cloud session;
- the owner decisions that fix the release identity (§4).

The brand identity is now frozen for 1.0: design gates 1 and 2 are closed,
gate 3 was waived (D-026) and gate 4 is deferred by the owner (D-031), not
passed. Brand decisions are
therefore off the critical path. What remains is:
- finishing E22;
- the identity cutover (#158);
- E23;
- the debt and licensing gates (#115, #148);
- the final string freeze (E16);
- distribution (E17).

At that baseline, the main risks were credentials and hosting that did not yet exist: an Apple
Developer ID, a Sparkle signing key, and website and archive hosting. Leaving
them to the end would stall E17. Non-goals: this page doesn't reorder the
epics, relax any gate, or authorise publication.

Terms used here:
- **RC:** release candidate, the exact build intended for publication.
- **Notarisation:** Apple's automated malware scan. It is required before
  Gatekeeper, macOS's download-verification check, lets a Developer ID app
  open without warnings.
- **Sparkle:** the open-source macOS update framework.
- **Appcast:** Sparkle's update feed.
- **EdDSA:** the signature scheme Sparkle uses to verify updates.
- **SBOM:** software bill of materials, a machine-readable list of every
  component shipped.

Status as of 2026-09-28, at `master` `8a05703`. Owner decisions recorded
2026-09-28 (§4).

## 1. Critical path

This is the hard order set by #158, `planning/RELEASE_HARDENING.md` and E17
(#18):

```text
E22 (#112) ─▶ identity inputs (#158) ─▶ E23 (#113) ─▶ S (software + UI stabilised, incl. #116–#121, #88, #79, #53)
    ─▶ private candidate 1 + software/native #115 verification (V1)
    ─▶ final E16 string freeze (#17)
    ─▶ final signed candidate 2 (needs the corresponding source already published, #148)
        + #148 exact-artifact compliance + artifact/locale-sensitive #115 reruns
    ─▶ #115 closes ─▶ full-history repository cutover (#158) ─▶ separately authorised public promotion (#18)

Source-only corresponding-source publication (#148, owner-authorised) happens BEFORE candidate 2 and never
publishes an application binary. Details: planning/RELEASE_SEQUENCE.md and compliance/ARCHIVE_PLAN.md.
Can be prepared early, used at E17:
    Developer ID certificate + notarisation profile (Mac tranche), Sparkle EdDSA key,
    website/archive hosting
```

E22 is being delivered slice by slice by its own session. Slices 1–6 have
landed (6c, recent files, in PR #161); 7 (folder search/replace), 8 and 9
remain. Nothing on this page interrupts that work.

Two technical fixes that blocked this path have landed (updated 2026-09-28,
after the status line above). Each was done on its own:
- **FileCore red `master` — fixed by PR #166 (`82ae971`).** The recurring
  `parentVanishedLatchSurvivesAChangedEventDuringDebounce()` failure was a
  test-harness race, separate from the recorder-ordering race fixed in #154: a
  superseded debounce probe consumed the test's scripted prober answers. It
  was reproduced (21 of 900 loaded iterations) and fixed by gating the
  interleaving deterministically, with exact-sequence assertions and a new
  regression test for the other ordering. No skips, and no longer timeouts.
  Product code was unchanged.
- **LC-05 (SwiftTreeSitter immutability, #148) — landed in #165**, after being
  updated onto the corrected `master` and getting a fresh green CI run.
  `MacDown2/Packages/MacDownKit/Package.resolved` is committed and pins
  SwiftTreeSitter at `cbe31cb3601aa29c1f64b6e4328733511126d6d5` (still
  declared `branch: "main"`, because Neon requires it). CI builds only locked
  revisions:
  - `swift build`/`swift test` run with `--force-resolved-versions`;
  - the Xcode builds copy the lock into the generated project, pass
    `-onlyUsePackageVersionsFromResolvedFile`, then check the copy survived.

  The enforcement covers CI only. A plain local `xcodebuild` resolves on its
  own unless the pin step in `AGENTS.md` is used; the same applies to any
  future release pipeline that does not use that step. The lock fixes *which*
  revisions are built. Checking them against a registered inventory is LC-07's job, and LC-07 is still open.
  Changing the lock is a deliberate dependency update, reviewed like code.

## 2. Workstreams

| Workstream | Owning issue | Can start now? | Where | Next concrete step |
|---|---|---|---|---|
| Brand identity | D-001–D-031 (`design/`) | **Done for 1.0** | — | None. Rename the Figma file title from "(Slant 12°)" in the Figma UI (D-029) |
| Branding cutover (repository, README, public copy) | #158 | Record only. #158 runs after E22 | Cloud | Inputs are decided (§4). Consume the identity inputs now; the repository cutover itself is the late full-history mirror to `Joncallim/mostlytext` after #115 closes (critical path above) — the engineering backlog stays in `macdown_2` until then, so do not transfer issues or rename early. Rebrand the README and public copy at the cutover, and classify the remaining `MacDown 2` references as #158 §4 requires |
| App-icon integration | E23 (#113); inputs from #158 | No. E23 follows #158 | Cloud edits; **Mac** to verify | Move `design/evidence/2026-09-26/icon-art/MostlyText-lean10.icon` into the app **next to** `Assets.xcassets`, not inside it, and remove `AppIcon.appiconset` and the placeholder script. See that folder's README (D-028). Verify in a Release build in the Dock and Finder, light and dark |
| Bundle identity and versioning | Strategy: #158. Migration: #18 | Decided | Cloud | Decided (§4): `app.mostlytext.MostlyText`, CLI `mostlytext`, version `1.0.0` with independent build numbers. Today the app is `com.joncallim.MacDown2`, `0.1.0 (1)`, CLI `macdown2`. E17 owns the switch and the migration of development-namespace state; E23 derives its Quick Look and theme identifiers from the new prefix |
| Licensing and notices | #148 (LC-01–LC-10) | **Yes.** LC-02–LC-07 are identity-neutral | Cloud | 1.0 ships under MIT; #148 LC-10 was reframed on 2026-09-28 to match. Third-party notices (LC-01 to LC-09) stay a hard gate. LC-05 (make SwiftTreeSitter immutable) needs a lock file, not a manifest pin: a `revision:` pin fails resolution because Neon's own manifest requires SwiftTreeSitter `branch: "main"`, and SwiftPM refuses two different revision-based requirements (CI, 2026-09-28). That fix landed in #165: a committed `Package.resolved` that CI enforces (§1; evidence in #148). The gate itself is in `compliance/` (2026-09-28): a checked inventory of all 33 shipped components, generated notices and SBOM, and a CI check with negative tests. LC-04 and LC-06 provenance are recorded there. `compliance.py check --release` lists what remains. Next: Mermaid's bundled npm dependencies (LC-01), the Graphviz and D2 source packages (LC-02/03, plan in `compliance/ARCHIVE_PLAN.md`). The inventory is reconciled with the #165 lock file: all 22 pinned revisions are verified, and `lockfile_enforced` is on, so a lock change that the inventory doesn't match fails CI. LC-08's licences screen (`compliance/LICENCES_UI.md`) starts after E22 and must land before the final E16 freeze |
| Trademark | D-031 | Nothing for 1.0 | — | Registration and legal review are **deferred by the owner, not passed**. The WIPO, USPTO and IPOS search record, including the flagged Modern Tech Pte. Ltd. mark (Singapore 40201616062P), stays in `design/brand/TRADEMARK_SEARCH.md` unchanged. Ship with no "®" and no clearance claim. Revisit if MostlyText gains material adoption, revenue or sponsorship, press recognition, third-party brand use or other brand value |
| Signing and notarisation | E17 (#18) | **Yes: Mac tranche ready** | **Mac** | Apple Developer Program enrolment is confirmed. `planning/MAC_SIGNING_BRIEF.md` is the bounded Mac task. It first confirms the Team ID and the Developer ID Application certificate, creating the certificate if it's missing. It then runs `release/macos/sign-notarize-dmg.sh --dry-run`, which: does a Release build with the hardened runtime; checks every binary's signature; checks the built app against the licence inventory; notarises and staples the app; notarises the CLI ZIP; builds, signs, notarises and staples a DMG; and validates everything with codesign, spctl and syspolicy_check. Last comes a clean-install Gatekeeper test of the DMG and the CLI ZIP in a fresh account. **The mode is explicit:** `--dry-run` records incomplete release gates as UNVERIFIED and continues. `--release-candidate` (E17 only) needs a clean tree and stops on any licence-gate failure, before anything is sent to Apple, and on a missing notarisation log. This tranche is a pre-cutover pipeline proof under the development identity, and it publishes nothing. The expected outcome is hardened runtime with no entitlements, made permanent for Release builds only. How the CLI finally ships (inside the app or as a separate download) is still an E17 decision |
| Packaging and downloads | E17 (#18) | Decided; build at E17 | Cloud plans; Mac builds | Decided (§4): a signed, notarised DMG on GitHub Releases, linked from `mostlytext.app`. The Sparkle EdDSA key is generated once, on a Mac, and stored in the owner's keychain or password manager, never in the repository |
| Website and deployment | E17 (#18); LC-09 (#148) | Draft exists | Cloud | `website/` (2026-09-28) has a static draft of `mostlytext.app`: home and download, `/opensource` archive and privacy pages. **Not deployed.** Its README has a claims ledger; every public statement needs release evidence before E17 deploys it. Hosting and the appcast are E17 decisions |
| Clean-install and update verification | E17 (#18); #115 | No. Needs the exact RC | **Mac** | On the signed, notarised RC: clean install on macOS 26 in a fresh user account or VM, Gatekeeper, first run, CLI, Sparkle N→N+1, migration from development state, legacy MacDown preference import (#53) |

## 3. Cloud and Mac split

Cloud sessions (Linux, no Xcode) own GitHub, planning, issue coordination,
documentation, CI configuration, website source, the licence and SBOM
tooling, Figma, and every source change that ordinary CI can check.

A Mac session is used only for what cannot run anywhere else:
- Developer ID certificates and keychain work;
- signing, notarisation and stapling;
- final Release builds;
- Gatekeeper and install tests;
- live Dock, Finder and Quick Look checks;
- executed XCUITests (#88).

No Mac environment is registered for cloud sessions. Mac work therefore runs
in the owner's local Claude Code on their own Mac, from a tightly scoped
brief. Each Mac brief must:

1. Name the exact commit or tag it works from, and the evidence it must
   return.
2. **Never publish.** No GitHub Release, appcast upload, website deploy or
   push to `master`. Evidence and small fixes go on a branch through a PR.
3. **Never commit credentials.** No certificates, `.p8`/`.p12` files, app
   passwords, notarytool profiles or Sparkle private keys, whether in the
   repository, in logs or in screenshots. Record only certificate names and
   Team ID, notarisation submission IDs and statuses, and hashes.
4. Stop and report when it hits a missing credential, a hardened-runtime
   problem that needs an architecture change, or anything that would change
   product behaviour.
5. Store evidence under `planning/evidence/YYYY-MM-DD/` (release; the folder
   doesn't exist yet and is created by the first Mac run) or
   `design/evidence/YYYY-MM-DD/` (visual), following
   `planning/RELEASE_EVIDENCE.md`'s rule that unavailable means `unverified`,
   never passed.

The first Mac brief is the signing and notarisation dry run described in
the table, written in `planning/MAC_SIGNING_BRIEF.md`. Enrolment is
confirmed, so it is ready to run. If the Developer ID certificate doesn't
exist yet, creating it is the brief's first bounded step.

## 4. Owner decisions (2026-09-28)

These fix the inputs #158 freezes and E17 applies.

| Topic | Decision |
|---|---|
| Product licence | **MIT** for 1.0 and normal 1.x releases, continuing MacDown's lineage. The proposed proprietary boundary in #148 LC-10 is withdrawn for 1.0, and LC-10 is reframed to keep the MIT licence and attribution accurate under the new name. Third-party licence notices, source availability and the SBOM check (LC-01 to LC-09) remain a **hard release gate** |
| Repository | Rename to **`Joncallim/mostlytext`** during #158. GitHub redirects old clone and web URLs, but CI, badges and links are still checked deliberately |
| Bundle ID | **`app.mostlytext.MostlyText`** (canonical). Extensions and theme or document identifiers use the `app.mostlytext.` prefix. E17 migrates state from the development ID `com.joncallim.MacDown2` |
| CLI | **`mostlytext`**. Whether `macdown2` survives as a temporary compatibility alias is an E17 migration detail, not a public name |
| Versioning | Marketing version starts at **1.0.0** and follows normal 1.x semantic versioning. `CFBundleVersion` is an **independent build number that only ever increases**, never reset per release (Sparkle compares it) |
| Distribution | Primary download is a **signed, notarised DMG on GitHub Releases**. **`mostlytext.app`** is the public download site. The appcast location and the website's source location are E17 architecture details that follow from this, with `https://mostlytext.app/appcast.xml` as the default |
| Apple Developer Program | Treated as **required** for public release: Developer ID signing and notarisation depend on it |

**Apple Developer Program status: enrolment confirmed** (owner, after
2026-09-28). It is no longer an open dependency. The Mac signing and
notarisation tranche (§2, §3) is ready to run.

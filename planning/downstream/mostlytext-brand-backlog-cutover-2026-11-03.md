# MostlyText brand and engineering backlog cutover

## Owner summary and baseline

MostlyText now owns its live engineering backlog and will ship the already-frozen
Slant app icon instead of the document placeholder. New users see MostlyText in
the welcome screen, sample and command help. Existing installations keep their
current bundle, preferences, storage and migration contracts. This is source
integration; Dock/Finder, clean-install, accessibility and signed-artifact
acceptance still require the protected native verification environment.

The owner explicitly requested transferring the 17 engineering issues and starting
brand identity cutover on 3 November 2026. This supersedes earlier instructions
to delay repository/backlog work until release. Baseline is MostlyText main
`26a876e8dde36c17e6f9912a8e2a0524951a5f61`. The display name and app ID are already
MostlyText and `app.mostlytext.MostlyText`; the internal app product remains
`MacDown2.app`. The production icon integration validated in D-028 was reverted
by the design lane, leaving the placeholder in current source. This pass consumes
D-027–D-031's existing frozen geometry, without redesign or legal-clearance claims.

## Journeys, boundaries and data flow

1. Existing issue links redirect to their transferred MostlyText issues; comments,
   labels, assignees, milestones and open state are preserved. The number map is
   recorded alongside this contract. Historical PR/release/test evidence stays
   at its original URL. Imported bare issue numbers retain their historical meaning.
2. A normal XcodeGen build compiles `MacDown2/MacDown2/AppIcon.icon`, adjacent to
   `Assets.xcassets`, using the existing AppIcon setting. It is a byte-identical
   copy of `design/evidence/2026-09-26/icon-art/MostlyText-lean10.icon`. Remove the
   competing placeholder appiconset. About uses the existing application-icon path.
3. First run uses that application icon, the MostlyText welcome title and sample;
   French/Japanese/Polish welcome translations retain their wording with the brand
   noun changed and review state reset. Generated example-command comments and
   command-folder and output-limit error copy use MostlyText. Their execution semantics do not change.

No new module, type, runtime service, persistence transition, executor, cancellation
policy or export path is introduced. SwiftUI/AppKit keep their existing ownership.
No user input, network access, font binary, executable or third-party artwork is
added. Register the two specific first-party icon files in Compliance; do not
relax ownership checks for an entire new asset directory. Build outputs must include
AppIcon.icns and Assets.car with appearance/tint renditions. Missing resources or
compilation errors block merge; a placeholder fallback is not an accepted result.

## Compatibility, accessibility and budgets

Keep internal target/module/product paths, executable names, app/extension/type IDs,
UserDefaults keys, recovery paths and legacy-import inputs unchanged. They are
not visible marketing text. Preserve original MacDown attribution, closed issues,
source tags, release assets and dated evidence. Keep development version 0.1.0;
this is not a release. No website deployment, signing or notarization occurs.

The decorative welcome image remains accessibility-hidden at its existing size;
controls/identifiers and native behavior stay unchanged. Update native UI fixture
expectations to the new welcome wording without weakening assertions. Catalog
review and actual localized layout remain open. Resource budgets, responsiveness,
parser/export/security invariants and all existing test deadlines remain unchanged.

## Slices, verification and stop conditions

- Transfer the original issues, after preserving snapshots and matching destination
  label/milestone metadata. Verify original redirect IDs and complete discussions;
  record exact old/new numbers before editing active references.
- Integrate the frozen icon and visible copy; update current documentation/templates,
  source/backlog links and the historical-number convention. Do not mass-renumber
  historical architecture or pretend dated native receipts qualify the new build.
- Regenerate the project with XcodeGen and restore pinned resolution. Run Compliance,
  formatter/linter, compile-only local Release build and inspect compiled metadata/
  icon renditions. Run the complete normal hosted app/package CI before merging.
  Run no local product or UI test under the owner account.
- Record actual results and remaining native acceptance in the identity issue.
  A changed storage requirement, different logo geometry, build-product rename or
  absent validated icon source requires a revised contract before implementation.

## Observed source and compiled-resource verification

The source tranche is `98d8ba01b492d52bc345f447be38f9110b18d018` (PR20). All 17
transfers were verified against complete saved bodies/discussions after normalizing
GitHub automatic cross-reference qualification/retargeting. Authors, original dates,
comment counts, labels (including colors/descriptions), assignees and milestone
titles match. Every old browser URL returns a redirect to the mapped issue; no
open engineering issue remains in the historical repository. A map note was then
added to each issue, with its prior body/discussion read back unchanged.

The locked local Release build compiles without executing the application. Its
Info.plist retains `app.mostlytext.MostlyText` and executable `MacDown2`, and uses
MostlyText for both bundle/display names. AppIcon.icns and Assets.car exist; the
compiled appearance table includes Aqua, DarkAqua, System and Tintable, with two
explicit tint renditions on Xcode 26.6. The extracted 256 px compiled icon shows
the approved Slant mark; both source files exactly match D-028's frozen document.
This observes compiled resources, not the live Dock/Finder appearance.

All 99 local Compliance controls pass; source and compiled-artifact inventory checks,
strict lint/format, dependency-pin checks and whitespace checks pass. The app's
project specification, dependency lock, migration environment, native launch guard,
LICENSE, release scripts and workflows match the baseline byte for byte. No local
product or UI test ran. Hosted CI results follow.

[Complete normal ARM CI41593264872](https://github.com/Joncallim/mostlytext/actions/runs/41593264872)
passes 3,325 package tests / 462 suites (340.511 seconds, two existing known Neon
issues), 600 app tests / 122 suites (128.855 seconds), locked Debug/Release app
and mostlytext builds, app/UI-test compilation, strict lint/format and final pins.
[Compliance41593264910](https://github.com/Joncallim/mostlytext/actions/runs/41593264910)
passes. PR20 merged at `d85cc9db03b50726c3967236704fcda45732f375`; its tree exactly
matches the tested head. This evidence follow-up changes documentation and JSON
indentation only; the application/design/release/lock inputs remain byte-identical.
The earlier pre-diagnostic-copy CI attempt was superseded/cancelled, not a pass.

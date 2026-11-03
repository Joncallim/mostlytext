# MostlyText repository migration

## Owner outcome and authorization

Give the application its own MostlyText repository while preserving the website,
its separate licence and every original source commit. On 3 November 2026 the
owner requested closing remaining PRs, commencing migration, and separating the
website into `mostlytext-site`. This explicitly authorizes repository preparation
now; it does not authorize release publication or waive any native/release gate.

## Baselines and preservation

Application: `Joncallim/macdown_2` master `8be8ad4158f6fee5ad8bd40337e118054177cfa8`,
tree `b021916cbe3bbdaf00ef863c568df563523953b5`. Full normal ARM CI41566262079
qualifies that exact source tree: 3,325 package tests (two pre-existing known
issues), 600 app tests, all locked Debug/Release app/CLI builds and lint.
Supplementary Intel native runs did not complete; their findings remain open.

Website: original `Joncallim/mostlytext` main `a5de8cd48666c10f0905f10e3a497b75bd5ef778`,
repository ID1396720903. Rename that repository to `Joncallim/mostlytext-site`,
preserving its history, branches, settings, separate licence and closed PR3.
Create a new public `Joncallim/mostlytext` for the application. Populate main from
the exact application commit and copy original tags; no force overwrite,
unrelated-history merge, history rewrite or default-branch deletion is needed.
Recovery bundles and before/after repository metadata are retained on Fast SSD.

## Scope and invariants

Keep all `MacDown2/`, `legacy-reference/`, design assets, dependency locks and
release scripts byte-identical. Change only current repository documentation,
the descriptive first-party licence heading, its six first-party theme licence
digests/generated notices, and CI branch admission. Preserve
all copyright and MIT terms. Native bundle/storage identifiers, product targets,
CLI semantics, signing, installation and runtime migration do not change.

Run normal app CI and Compliance for main. Preserve master/integration-final
admission for historical source reuse; scope the old PR535-only diagnostic to
its original repository, so an unrelated future MostlyText PR535 cannot enable it.
No test assertions, deadlines, skips or known-issue classifications are relaxed.

## Backlog, artifacts and public links

The 17 engineering issues remain in `Joncallim/macdown_2` with their current
numbers and evidence. Imported bare issue numbers belong to that historical
backlog. Transfer is a separate mapped operation; do not recreate issues or make
old numbers refer to unrelated new issues. Closed drafts519/520 retain their
branches and pending requirements in original issues121/112. The website's
closed editorial PR3 is preserved in `mostlytext-site`.

Canonical new application/source links point to `Joncallim/mostlytext`; website
source links point to `Joncallim/mostlytext-site`. Old issue, PR, alpha-release
asset and evidence links remain at their original repository. The website is
source-only here; no Cloudflare deployment, feed, DNS, secret or release is changed.

## Verification and completion boundary

Verify new main and all copied tag targets against the source; verify both
histories and the website's unchanged main before further edits. Confirm app
and legacy subtrees remain identical. Run current Compliance controls/inventory,
strict lint/format and the normal hosted checks admitted on main. Update the
source-tracking issue158 with exact repository links and proof.

This completes repository separation and starts the application migration. It
is not full identity/release completion: original issue158's packaged identity,
installation, automation and remaining public-link criteria stay open; issue115,
native protection/account/control, licensing/artifact, performance, languages and
signing/update obligations are unchanged. Existing native receipts remain bound
to their actual built source and original canonical worktree, never retargeted.

The initial inventory check correctly rejects the changed root-licence digest in
six first-party theme entries and stale notices. Preserve that failure, verify
the sole descriptive-word replacement with all MIT terms/copyright unchanged,
then refresh only those six licence digests and regenerate notices/SBOM. No
third-party text, theme data or dependency resolution changes.

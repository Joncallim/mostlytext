# Identity handoff and acceptance readiness

## Owner summary and baseline

The owner asked to run native/signing acceptance here, or continue closing source
brand and documentation work if unavailable. Baseline is MostlyText main
`f660e30f61c0b48551fb450ee9afd24ba35d50ae`. This tranche reconciles current source,
public identity assets and release instructions; it does not change application,
storage, migration, entitlement, dependency or test behavior.

## Observed prerequisites — CORTANA, 3 November 2026

- Console/agent user is UID501. mostlytexttest exists as UID502 but has no GUI
  domain. /Library/MostlyTextVerification is absent and nonprompting sudo refuses.
  The existing protected native executor cannot safely run in this session.
- security find-identity reports a valid Developer ID Application identity for
  team 968BRM85G5. The actual signing script's preflight-only mode finds it, then
  stops because the documented mostlytext-notary keychain profile does not exist.
  No build, signature, notarization submission or product execution occurs in
  that mode. Certificate presence does not prove key authorization/signing.
- The strict release check against the compiled brand candidate reports six
  existing D2/Mermaid/Graphviz provenance/source-publication failures. This is
  distinct from the passing source and nonrelease artifact inventory checks.

## Source work and invariants

Publish one current identity handoff covering implemented names, migration-sensitive
legacy identifiers, reserved future extension/resource names and unfinished native
acceptance. Close only source/documentation checklist items that the live source
and frozen assets support. Keep whole engineering issues open when their broader
native, correctness, performance, translation or exact-artifact criteria remain.

Produce a repository social image by composing the existing canonical outlined
lockup on an opaque white canvas at GitHub's recommended dimensions. It introduces
no font or logo geometry. Track its generator and render via a browser for visual
inspection; verify dimensions/size. Use existing repository settings to install
this image after inspection, if browser authorization is available. Keep website
licensing and deployment independent. Correct the Figma title through its visible
file-name control without changing canvas geometry or historical decision records.

Current documentation points to main and MostlyText issue numbers; dated source,
release, PR and native receipts retain their original URLs/hashes. Do not retarget
old protected native receipts to this new source or weaken isolation, tests,
compliance, signing or final release gates. Missing credentials are recorded,
never inferred or copied from unrelated accounts.

## Verification

Run source Compliance and required hosted checks; inspect rendered social artwork
and visible website-setting readback. Compare application/design masters/release
scripts/locks/license/workflows against the baseline. Documentation and first-party
brand exports do not require repeating unchanged product tests. Native/signing
acceptance remains separate. Record actual results in the relevant issues.

## Observed brand completion and limits

The Figma title-only D-029 follow-up is complete: the visible control now reads
“MostlyText — Brand Identity (Slant 10°)”. Artwork was unchanged and a screenshot
was saved. The repository preview SVG rebuilds byte for byte from the canonical
lockup; browser-rendered JPEG is 1280×640 and 23,896 bytes, with no bundled font.
Visual inspection confirms the approved lockup, legible on the opaque white canvas.

The GitHub settings upload did not persist on reload. The native file-chooser
fallback refused because the Mac is locked; no social-preview installation is
claimed. The source asset and its provenance remain ready, with installation
tracked separately. This does not require reopening the frozen design.

Application/release/workflow/license/inventory inputs and frozen geometry masters
are unchanged from the baseline; the modified/new Markdown local links resolve.
Source Compliance passes. Tests and merge evidence follow in the PR and issues.

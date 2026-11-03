# Preserve failed notarization evidence before stopping the release pipeline

## Owner summary

A notarization submission command can return an error after producing a response.
The script currently stops before saving that response or fetching its rejection
log. Preserve stdout, stderr and exit status first; validate the response, retrieve
its log when a safe ID exists, then enforce the failure. This improves diagnostic
evidence without authorizing or claiming real signing/notarization acceptance.

## Baseline and scope

Main 1abee55cc758d9b9abdab2d7429f4af96fb3149b. The script/test sources are identical
to 3f7b4bdc, where a real owned fixture demonstrated exit 65 with neither the
submission JSON nor rejection log preserved. All Apple commands were substitute
executables in a temporary repository. Real credentials/services were not used.
Owners: MostlyText #4 release engineering and #14 exact-artifact gates.

Allowed: release/macos/sign-notarize-dmg.sh, behavioral substitute-tool tests and
release/acceptance documentation. No app/runtime/pin/notice/SBOM inputs, build,
signing/notary/profile/feed identities, source-publication authority or release
tolerance change. Tests must remain wholly owned fixtures with substitute Apple
tools. Do not execute the real pipeline or provision credentials.

## Behavior and failure contract

The common app/CLI/DMG submission function writes the tool's complete stdout,
stderr and numeric exit status to its phase-specific evidence before any parsing
or failure. Validate one JSON object with unique keys, string ID and status;
reject malformed/duplicate/nonfinite values and missing/empty/option-like IDs.
Use bounded safe field syntax so untrusted response text cannot become log options
or multiline summary content. Preserve raw response/validation diagnostics.

If a valid submission identity is available, attempt log capture before judging
submission status/exit. Keep log diagnostics and exit evidence. Non-Accepted
status or a nonzero submission command exit always stops every mode, even if the
payload claims Accepted. Missing logs keep the existing dry-run UNVERIFIED versus
strict-candidate stop rule. Missing/invalid identity stops with preserved evidence
and no guessed log request. Never retry, waive a failed submission or proceed to
later packaging/promotion after failure.

## Verification and completion

Extend behavioral fixtures for nonzero Invalid/Accepted responses, empty/non-JSON/
malformed/duplicate fields and unsafe IDs. Cover app, CLI and DMG failures without
real tools; prove response/stderr/status/log evidence and absence of later steps.
Retain passing existing mode, lock, CLI packaging and gate controls. Run the full
compliance suite and shell syntax, source checks, exact-head hosted Compliance and
merge-tree proof before integration. Update #4/#14 source criteria; real signing,
notarization, installed-state, independent review and six strict gates stay open.

# Distribute the CLI with the app that owns its identity

## Owner summary

The release pipeline must not offer an independent executable that cannot open
documents under its own security contract. Keep the public command mostlytext,
build it with MostlyTextCLI, and distribute its embedded mostlytext-cli copy
inside the signed app/DMG. Users may explicitly create a symlink to that copy.
Remove the separate unsupported bare-binary CLI ZIP from future release output;
keep every existing signed artifact and download untouched. This is packaging
consistency, not a new application resolver, signing run or public release.

## Live baseline and reconciled contract

Live mainf9f14670dcf3aef953596a81d442a28ec9ca091b includes PR109's source-only
D2 evidence. Read root AGENTS, EPIC_STANDARD, RELEASE_HARDENING, RELEASE_SEQUENCE,
epic-17-implementation, issue-18-handoff and the installation guide. The binding
CLI contract explicitly bundles the helper in its signed app with an optional
user-created symlink; no PATH lookup or configurable app identity is allowed.
EmbeddedCommandApplication.locate resolves that symlink and requires the actual
Contents/MacOS/mostlytext-cli container. The installation guide correctly warns
that copying it out loses required app identity/resources. Cold launch also
requires Apple-anchored app and matching embedded-CLI team signatures.

The release script instead notarises/distributes mostlytext.zip containing the
bare separately built executable, calls it a standalone installation, and lists
it as a public distributable. These claims contradict the current real code and
binding app-plus-symlink contract. The fixed build target/public command names
are already correct; do not rename those or relax any container/signature check.

## Narrow change and failure model

Keep both locked Release builds, explicit built/embedded CLI existence/executable/
identity checks, every Mach-O signature/team/hardened-runtime/timestamp/nested
check, exact-artifact compliance, app notarisation+stapling, DMG signing/notary/
stapling/Gatekeeper, source cleanliness and publication gates. App notarisation
covers the helper inside that same signed app. Only the separate bare-CLI ZIP
submission/distribution is removed. Hash the DMG as the sole distributable and
retain app-ZIP/bare-build/embedded-helper hashes as non-distributed audit inputs.
Record the supported app-plus-explicit-symlink installation in summary/docs.
No keychain/signing/notary/public CLI/app/native execution occurs locally.

If an explicitly reused output directory already contains the old unsupported
mostlytext.zip, preserve its bytes and stop a full pipeline before build or
Apple contact, requiring a fresh output directory. Do not delete or relabel a
previous artifact. Preflight-only retains its read-only signing-prerequisite
behavior and produces no install/artifact. No installer, shell-profile edit,
symlink creation, sudo, default-app change, old release deletion or publishing.

## Verification

First retain a regression failure from the old script producing/listing the
unsupported standalone ZIP. Update phase coverage to both actual notarisation
objects (app,DMG), preserving every rejected/nonzero/transport/malformed/log
failure assertion and original signing/embedded-helper checks. Require future
success to build the public mostlytext product, verify the embedded copy, emit
no standalone ZIP/public hash, and preserve/refuse an old artifact. Verify the
new non-distributed helper hash and exact summary. Run pure release-script tests,
all compliance controls and inventory, shell syntax and source review, require
all exact-head hosted checks and tree equality before expected-head merge.
Do not invoke the real release script, credentials or native executables.

## Native acceptance remains separate

Hosted warm public CLI/app acceptance may be investigated independently using a
fresh ephemeral macOS26 account, the real embedded helper/user-owned symlink and
ordinary app launch/file events. Unsigned/ad-hoc cold launch must still refuse;
Apple-trusted cold launch and signed installed-candidate acceptance remain the
existing gated work. No warm or fixture result substitutes for those criteria.
The current Preview diagnostic branch and its retained original failures are
unrelated; this packaging-only unit need not wait for that production merge.

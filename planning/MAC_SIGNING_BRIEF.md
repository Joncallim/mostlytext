# Mac tranche: Developer ID signing, notarisation, DMG and clean-install check

**Owner summary.** This is the Mac-only part of the release pipeline, run as
one bounded session on the owner's Mac. It:
- confirms the Apple Developer account's Team ID and the Developer ID
  signing certificate, creating the certificate first if it doesn't exist;
- builds a Release candidate with the hardened runtime (macOS's
  code-integrity protection, which notarisation requires);
- signs, notarises and staples it (stapling attaches Apple's approval ticket
  to the file, so Gatekeeper can check it offline);
- packages it as a signed, notarised DMG;
- checks that a fresh install opens cleanly through Gatekeeper, macOS's
  download check.

The aim is to prove the whole pipeline and fix any signing or entitlement
problem now, rather than during E17. It publishes nothing.

**Current status — 3 November 2026.** Application source and the engineering
backlog are now in `Joncallim/mostlytext` on `main`. The app uses display name
MostlyText and bundle ID `app.mostlytext.MostlyText`; the internal build product
remains `MacDown2.app`. The public CLI is `mostlytext`, built with scheme
`MostlyTextCLI` (target/module `MostlyTextCommand`), with required embedded
helper `Contents/MacOS/mostlytext-cli`.

Actual CORTANA checks found a valid **Developer ID Application: Jonathan Lim
(968BRM85G5)** identity. The documented script's `--preflight-only` mode then
stopped because keychain profile `mostlytext-notary` is absent. Certificate
presence completes discovery, not an actual signing/notarization proof. No new
certificate or key export is needed merely to repeat this discovery.

Native acceptance is also blocked in the current session: UID501 is the console
user, mostlytexttest (UID502) has no GUI domain, protected staging is absent and
nonprompting administrator access is unavailable. Existing native receipts remain
bound to their original source; do not repoint them at a different build.

The strict release check against the compiled brand candidate reports **six**
existing D2/Mermaid/Graphviz provenance/source-publication failures under
[MostlyText #14](https://github.com/Joncallim/mostlytext/issues/14). Source and
nonrelease artifact checks pass. These are different gates. See
[acceptance status](ACCEPTANCE_STATUS.md) and [identity handoff](IDENTITY.md).

Nothing produced by this preparatory work is published. Application code,
credentials, signing policy and native protection are not changed by this brief.

## Rules

1. **Never publish.** No GitHub Release, tag, appcast, website deploy,
   notarised file upload, or direct push to `main`. Changes and evidence go on a
   branch through a pull request.
2. **No credentials in the repository, logs or screenshots.** That covers
   certificates, `.p12`/`.cer`/`.p8` files, private keys, app-specific
   passwords, App Store Connect API keys, and keychain profile contents.
   Record only the certificate's common name, the Team ID, notarisation
   submission IDs and statuses, and hashes. The Team ID isn't secret (it's in
   every signature), but keep it out of `project.yml` for now: the script
   takes it as input, and E17 decides how the release build receives it.
3. **Stop and report** instead of improvising if any of these happen: the
   Apple account lacks the role needed to create a Developer ID certificate;
   notarisation rejects something that needs a code or architecture change;
   or the app needs an entitlement that isn't covered by step 2 below.
   Report the exact output; the fix is planned in the cloud.
4. **Only the changes listed here.** Don't change app code, and don't add
   entitlements "just in case".

## Step 0: Team ID and Developer ID certificate (first bounded step)

1. Find the Team ID: developer.apple.com → Account → Membership details.
   Record it.
2. Check for an existing certificate:
   `security find-identity -v -p codesigning | grep "Developer ID Application"`.
   A line ending in `(<TEAM_ID>)` means it exists; go to step 1.
3. If it doesn't exist, create it in Xcode: Settings → Accounts → select the
   team → Manage Certificates → **+** → **Developer ID Application**. This
   needs the **Account Holder** role, which the owner has as an individual
   enrollee. Xcode generates the private key in the login keychain and never
   writes it to disk.
4. **Back up the private key outside the repository.** Export the identity
   from Keychain Access as a password-protected `.p12`, and store the file
   and its password in the owner's password manager. Losing it means
   creating a new certificate, not a lost release, but a backup avoids that.
   Never put the `.p12` anywhere under the repository.
5. Create the notarisation keychain profile, stored only in the keychain:
   `xcrun notarytool store-credentials mostlytext-notary --apple-id <id> --team-id <TEAM_ID>`
   (it prompts for an app-specific password from appleid.apple.com), or use
   `--key/--key-id/--issuer` with an App Store Connect API key.
6. Run the preflight:
   `TEAM_ID=<TEAM_ID> NOTARY_PROFILE=mostlytext-notary release/macos/sign-notarize-dmg.sh --preflight-only`.
   It checks the identity and the profile only. It performs no build,
   signing or notarisation submission, and makes no repository changes. It
   does write its log and evidence to the git-ignored `build/` folder.

## The script's three modes

The mode is a required argument, so the script never has to guess from a
file name or label whether a failure is acceptable.

| Mode | Use | If the licence gate or notarisation log fails |
|---|---|---|
| `--preflight-only` | Step 0 | Not reached; nothing is built |
| `--dry-run` | **This tranche.** Proves the pipeline on a pre-cutover build that is never published | Recorded as `UNVERIFIED (dry run)` in `summary.txt`; the run continues |
| `--release-candidate` | **E17 only**, for a build that may be published | The run stops. A failing licence gate stops it before anything is sent to Apple. It also refuses to start from a working tree with uncommitted changes |

The licence gate is `compliance.py check --release --artifact <app>`. Its
current six failures concern D2 source hosting/review, Mermaid bundled dependency
versions/licenses, and Graphviz source hosting/corresponding-source/embedded
attribution review. The committed dependency lock and offline license surfaces
already exist; do not repeat the old claim that LC-05/LC-08 have no implementation.
Their complete native/exact-artifact acceptance remains in #14. Dry-run tolerance
is pipeline evidence, not permission to call these release gates passed. A release
candidate must pass the strict check before anything is submitted to Apple.

## Step 1: build, sign, notarise and package

The script is already integrated in the application repository. Start a clean
working branch from the current reviewed `main`; [original PR164](https://github.com/Joncallim/macdown_2/pull/164) references describe its
original introduction, not an unmerged prerequisite. The following is the
preparatory pipeline mode, not a final release command:

```sh
git fetch origin
git switch -c release/signing-dry-run origin/main
TEAM_ID=<TEAM_ID> NOTARY_PROFILE=mostlytext-notary release/macos/sign-notarize-dmg.sh --dry-run
```

`release/macos/sign-notarize-dmg.sh` stops at the first failure. It does the
following:

1. **Release build** of the app and the CLI with the hardened runtime, the
   Developer ID identity and secure timestamps.
2. **Signature check.** It verifies that every Mach-O binary is signed by
   this Team ID's Developer ID, with the hardened runtime and a timestamp.
3. **Licence gate** against the built app, before anything goes to Apple.
   It confirms by SHA-256 that every inventoried runtime resource is in the
   app (the diagram engines, themes, grammar queries and all 12 SwiftUIMath
   fonts), along with the notices file and `LICENSE`, and that no
   unregistered script, WebAssembly or font file ships. In a dry run the
   result is recorded (see the modes table).
4. **Notarise the app** (zipped) and staple it, and download Apple's
   notarisation log. A log that can't be downloaded is recorded as
   `UNVERIFIED` in a dry run and stops a release candidate.
5. **Notarise the CLI ZIP.** A bare command-line binary can't be stapled, so
   Gatekeeper checks its ticket online. The notarised ZIP is the CLI's
   distributable form for now (see the note in step 3 below).
6. **Build the DMG,** containing the app and an Applications shortcut. Then
   sign it, notarise it and staple it.
7. **Validate** with `stapler validate`, `spctl` (app and DMG),
   `codesign --verify`, and `syspolicy_check distribution`, Apple's
   pre-distribution check.
8. **Record** SHA-256 hashes. The distributables are the DMG and the CLI ZIP.

Output goes to `build/release-<timestamp>/`, which is git-ignored.

## Step 2: hardened runtime and entitlements

The expected result is **hardened runtime with no entitlements**:
- The app isn't sandboxed (MIGRATION_PLAN D7).
- Diagram rendering uses WKWebView, whose web content runs in Apple's own
  processes, so the app needs no JIT (just-in-time compilation) entitlement.
- User text filters are started with `Process`, which the hardened runtime
  allows.

Confirm this with the smoke test in step 3.

- **If everything works:** make the setting permanent in a small PR. In
  `MacDown2/project.yml`, set `ENABLE_HARDENED_RUNTIME: YES` in the **Release**
  configuration of the `MacDown2` and `MostlyTextCommand` targets only. Debug builds
  and CI's unsigned test runs stay unchanged, so tests are unaffected.
  Regenerate the project with `xcodegen generate` and confirm the Release
  build.
- **If a feature fails only under the hardened runtime:** capture the console
  error, identify the single entitlement it needs, re-run with
  `ENTITLEMENTS=<file>`, and commit that `.entitlements` file with the
  evidence explaining why it's needed. If more than one entitlement seems
  necessary, or the fix isn't obvious, **stop and report** (rule 3).

## Step 3: clean-install and Gatekeeper test

Use the protected test-account workflow or an approved fresh macOS 26 virtual
machine, with isolated fixtures, no existing preferences/trust decisions and
fresh isolation controls. Do not substitute the owner's current UID501 session.
Build/static preflight is not executed UI evidence; current prerequisite failures
are recorded above.

1. Get the DMG into that account **with the quarantine flag set**, the way a
   real download would. AirDrop it, or download it with Safari from private
   storage. Confirm with
   `xattr -p com.apple.quarantine <dmg>`. If neither is possible, set the
   flag by hand and record that you did:
   `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <dmg>`.
2. Open the DMG. Record whether Gatekeeper shows any warning. None is
   expected for a notarised, stapled DMG.
3. Drag the app to Applications and launch it. Expect only the standard
   "downloaded from the Internet" confirmation, with Apple's malware check
   passed. Then disconnect from the network and launch again: it must open
   with no warning, which shows the stapled ticket works offline.
4. Smoke test, with the network off:
   - open a Markdown file;
   - preview a math block and Mermaid, Graphviz and D2 diagrams;
   - export to HTML and to PDF;
   - run one text filter;
   - quit and relaunch to check session restore.

   Record any feature that fails and the console errors (Console.app, filtered
   on the app).
5. CLI, starting from the file a user would download:
   - get `mostlytext.zip` (the notarised ZIP from `build/`) into the fresh
     account **with the quarantine flag set**, as for the DMG in item 1, and
     confirm it with `xattr -p com.apple.quarantine mostlytext.zip`;
   - extract it with Finder (double-click), which carries the quarantine flag
     over to the extracted `mostlytext`; confirm that with `xattr -l mostlytext`;
   - run `./mostlytext formats` from Terminal, first online and then offline,
     and record any Gatekeeper prompt or refusal.

   The app embeds `mostlytext-cli`; the public `mostlytext` command supports
   explicit installation using that helper, and the release script also
   produces a standalone ZIP. This acceptance step proves the downloaded ZIP
   under quarantine. The app install/remove command flow and embedded helper
   still need their own native acceptance; source tests do not complete either
   gate. Record exactly which distribution path was exercised.
6. Remove the test account or VM afterwards.

## Evidence to return

Open **one pull request** from `release/signing-dry-run` containing:

- `planning/evidence/<YYYY-MM-DD>/signing-dry-run/`:
  - `README.md`: commit SHA, macOS and Xcode versions, the certificate's
    common name, the Team ID, and a pass/fail table for steps 0 to 3. Mark
    anything skipped as `unverified`, never passed
    (`planning/RELEASE_EVIDENCE.md`).
  - From the script's `evidence/` folder: `summary.txt`, `verify.txt`,
    `macho-signatures.txt`, `codesign-display-*.txt`, `notary-*-submit.json`,
    `notary-*-log.json`, `SHA256SUMS`, `compliance-artifact.txt`. These
    contain no secrets. Read them once before committing anyway.
  - Copy every `UNVERIFIED (dry run)` line from `summary.txt` into the README
    table. In particular, list each `compliance-artifact.txt` failure as a
    known release gate (for example "LC-08: notices file not bundled"), not
    as a pass.
  - The clean-install and smoke-test results, with screenshots of the
    Gatekeeper dialogs. Screenshots must show no keychain or account details.
- If step 2 passed cleanly: the Release-only hardened-runtime change to
  `project.yml`. If an entitlement was needed: its file and the reason.

**Do not commit** the DMG, the zips, the app, the `DerivedData` folder or
`run.log` (the log is only for your own debugging). They stay in the
git-ignored `build/` folder.

The reviewer reconciles the PR, `RELEASE_PATH.md` and
[distribution issue #4](https://github.com/Joncallim/mostlytext/issues/4),
and plans any fix.

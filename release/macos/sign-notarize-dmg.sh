#!/usr/bin/env bash
# Build, sign, notarise and package MostlyText.app as a
# Developer ID DMG, and record evidence. Runs on the owner's Mac only.
#
# What it does, in order (stops at the first failure):
#   1. preflight  Team ID, Developer ID Application identity, notarytool profile
#   2. build      Release build of the app and CLI with the hardened runtime
#   3. sign-check confirm Xcode signed every Mach-O binary with this Developer
#                 ID, the hardened runtime and a secure timestamp
#   4. licences   compliance.py check --release --artifact against the built app
#   5. notarise   submit the app (including its CLI), wait, save logs, staple the app
#   6. dmg        build a DMG (app + /Applications link), sign, notarise, staple
#   7. verify     codesign, spctl, stapler validate, syspolicy_check
#
# The mode is a required argument, so failure tolerance is always a
# deliberate choice, never inferred from a file name or label:
#   --preflight-only     step 1 only. No build, no signing, no notarisation
#                        submission, and no repository changes. It does write
#                        its log and evidence to the git-ignored output folder.
#   --dry-run            the whole pipeline, as a pipeline proof. Known-incomplete
#                        release gates are recorded, not fatal: a failing
#                        licence check (step 4) or a notarisation log that
#                        can't be downloaded is written to the evidence as
#                        UNVERIFIED and the run continues. Never publish its output.
#   --release-candidate  the whole pipeline for a candidate that may be
#                        published. Requires a clean working tree. Any licence
#                        check failure stops the run before anything is sent to
#                        Apple, and a notarisation log that can't be downloaded
#                        stops it too. Used by E17.
#
# Secrets never pass through this script or its logs. Signing uses the
# certificate already in the login keychain; notarisation uses a keychain
# profile created beforehand with `xcrun notarytool store-credentials`.
# Evidence records only certificate names, the Team ID, submission IDs,
# statuses and hashes.
#
# Usage:
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=mostlytext-notary \
#     release/macos/sign-notarize-dmg.sh --preflight-only|--dry-run|--release-candidate
#
# Optional environment:
#   ENTITLEMENTS  path to an .entitlements file (default: none)
#   OUT           output directory (default: build/release-<UTC timestamp>)

set -euo pipefail

: "${TEAM_ID:?set TEAM_ID to the Apple Developer Team ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to the notarytool keychain profile name}"
ENTITLEMENTS="${ENTITLEMENTS:-}"
case "${1:-}" in
  --preflight-only)    MODE=preflight ;;
  --dry-run)           MODE=dry-run ;;
  --release-candidate) MODE=release-candidate ;;
  *) echo "usage: $0 --preflight-only|--dry-run|--release-candidate" >&2; exit 2 ;;
esac

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_PACKAGE_RESOLVED="$REPO/MacDown2/Packages/MacDownKit/Package.resolved"
SOURCE_PACKAGE_RESOLVED_REL="MacDown2/Packages/MacDownKit/Package.resolved"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT:-$REPO/build/release-$STAMP}"
EVIDENCE="$OUT/evidence"
DERIVED="$OUT/DerivedData"
APP_SCHEME="MacDown2" # internal Xcode target and build product
APP_NAME="MostlyText" # public app, ZIP, DMG and Finder name
APP_ARCHIVE_NAME="$APP_NAME-app.zip" # distinct from obsolete mostlytext.zip on case-insensitive volumes
CLI_NAME="mostlytext"
CLI_SCHEME="MostlyTextCLI" # distinct from the app scheme on case-insensitive volumes
mkdir -p "$EVIDENCE"
exec > >(tee -a "$EVIDENCE/run.log") 2>&1

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nSTOP: %s\n' "$*"; exit 1; }
record() { printf '%s\n' "$*" >> "$EVIDENCE/summary.txt"; }

record "commit: $(git -C "$REPO" rev-parse HEAD)"
record "dirty: $(git -C "$REPO" status --porcelain | wc -l | tr -d ' ') changed paths"
record "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
record "xcode: $(xcodebuild -version | tr '\n' ' ')"
record "team: $TEAM_ID"
record "mode: $MODE"

# In dry-run mode a known-incomplete gate is recorded and the run continues;
# in release-candidate mode the same condition stops it.
gate() {  # $1 message
  if [[ "$MODE" == "release-candidate" ]]; then
    fail "$1"
  fi
  record "UNVERIFIED (dry run): $1"
  printf '\nUNVERIFIED (dry run, continuing): %s\n' "$1"
}

if [[ "$MODE" == "release-candidate" && -f "$SOURCE_PACKAGE_RESOLVED" ]] \
  && { ! git -C "$REPO" diff --quiet HEAD -- "$SOURCE_PACKAGE_RESOLVED_REL" \
       || ! git -C "$REPO" diff --cached --quiet -- "$SOURCE_PACKAGE_RESOLVED_REL"; }; then
  fail "the source Package.resolved differs from the committed lock before Xcode generation"
fi

if [[ "$MODE" == "release-candidate" && -n "$(git -C "$REPO" status --porcelain)" ]]; then
  fail "a release candidate must be built from a clean working tree; commit or stash first"
fi

if [[ "$MODE" != "preflight" ]]; then
  # A reused output directory may contain the unsupported standalone artifact
  # produced by older pipeline versions. Preserve it and require a fresh output.
  [[ ! -e "$OUT/$CLI_NAME.zip" && ! -L "$OUT/$CLI_NAME.zip" ]] \
    || fail "obsolete standalone CLI ZIP exists in the output directory; preserve it and use a fresh OUT"
fi

# ---------------------------------------------------------------- 1. preflight
step "Preflight: Developer ID Application identity for team $TEAM_ID"
IDENTITIES="$(security find-identity -v -p codesigning)"
IDENTITY_LINE="$(grep "Developer ID Application: .*($TEAM_ID)" <<<"$IDENTITIES" | head -n 1 || true)"
[[ -n "$IDENTITY_LINE" ]] || fail "no valid 'Developer ID Application: … ($TEAM_ID)' identity in the keychain. Create it first (brief step 0)."
IDENTITY="$(sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' <<<"$IDENTITY_LINE")"
record "identity: $IDENTITY"
echo "Using: $IDENTITY"

step "Preflight: notarytool profile '$NOTARY_PROFILE'"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null \
  || fail "notarytool profile '$NOTARY_PROFILE' is missing or rejected. Create it with xcrun notarytool store-credentials."
record "notary profile: present"

if [[ -n "$ENTITLEMENTS" ]]; then
  [[ -f "$ENTITLEMENTS" ]] || fail "ENTITLEMENTS file not found: $ENTITLEMENTS"
  record "entitlements: $ENTITLEMENTS ($(shasum -a 256 "$ENTITLEMENTS" | cut -d' ' -f1))"
else
  record "entitlements: none"
fi

if [[ "$MODE" == "preflight" ]]; then
  echo "Preflight passed. Nothing was built, signed or submitted. Evidence: $EVIDENCE"
  exit 0
fi

# ---------------------------------------------------------------- 2. build
# XcodeGen recreates the project-local SwiftPM workspace.  Its generated
# Package.resolved is deliberately untracked, so copy the reviewed
# MacDownKit lock into that workspace before asking Xcode to build.  The
# helper also makes the expected generated-project location explicit.
PIN_XCODE_PACKAGES="$REPO/MacDown2/scripts/pin-xcode-package-versions.sh"
[[ -f "$SOURCE_PACKAGE_RESOLVED" ]] \
  || fail "the committed MacDownKit Package.resolved lock file is missing"
[[ -x "$PIN_XCODE_PACKAGES" ]] \
  || fail "the Xcode package pin helper is missing or not executable: $PIN_XCODE_PACKAGES"

# A release candidate must start from the reviewed repository lock.  Dry runs
# may intentionally exercise a dirty tree, but make that exception explicit
# in their evidence rather than presenting it as a committed resolution.
if ! git -C "$REPO" diff --quiet HEAD -- "$SOURCE_PACKAGE_RESOLVED_REL" \
  || ! git -C "$REPO" diff --cached --quiet -- "$SOURCE_PACKAGE_RESOLVED_REL"; then
  gate "the source Package.resolved differs from the committed lock before Xcode generation"
fi
SOURCE_PACKAGE_RESOLVED_SHA256="$(shasum -a 256 "$SOURCE_PACKAGE_RESOLVED" | awk '{print $1}')"
[[ -n "$SOURCE_PACKAGE_RESOLVED_SHA256" ]] \
  || fail "could not calculate the source Package.resolved digest"
record "source Package.resolved sha256: $SOURCE_PACKAGE_RESOLVED_SHA256"

step "Generate the Xcode project"
(cd "$REPO/MacDown2" && xcodegen generate)
"$PIN_XCODE_PACKAGES" \
  || fail "could not copy the committed Package.resolved into the generated Xcode workspace"

build() {  # $1 scheme, $2 "app" to apply ENTITLEMENTS
  local extra=()
  [[ -n "$ENTITLEMENTS" && "${2:-}" == "app" ]] && extra+=(CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS")
  xcodebuild -project "$REPO/MacDown2/MacDown2.xcodeproj" -scheme "$1" \
    -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
    ${extra[@]+"${extra[@]}"} build
}
step "Release build: $APP_SCHEME"
build "$APP_SCHEME" app
step "Release build: $CLI_NAME"
build "$CLI_SCHEME"

# Do not package a release if either Xcode build rewrote or removed the
# generated workspace lock.  This is intentionally after both builds: it
# checks the resolution that produced every artifact below.
[[ "$(shasum -a 256 "$SOURCE_PACKAGE_RESOLVED" | awk '{print $1}')" == "$SOURCE_PACKAGE_RESOLVED_SHA256" ]] \
  || fail "the source Package.resolved changed during the Release builds"
"$PIN_XCODE_PACKAGES" --check \
  || fail "the generated Xcode workspace Package.resolved changed during the Release builds"

PRODUCTS="$DERIVED/Build/Products/Release"
BUILT_APP="$PRODUCTS/$APP_SCHEME.app"
APP="$OUT/$APP_NAME.app"
CLI="$PRODUCTS/$CLI_NAME"
EMBEDDED_CLI="$APP/Contents/MacOS/mostlytext-cli"
[[ -d "$BUILT_APP" && ! -L "$BUILT_APP" ]] || fail "app not produced at $BUILT_APP"
[[ ! -e "$APP" && ! -L "$APP" ]] || fail "public app already exists at $APP; use a fresh OUT"
ditto "$BUILT_APP" "$APP" || fail "could not stage the signed public app at $APP"
record "public app: $APP_NAME.app (built from $APP_SCHEME.app without modifying its contents)"
[[ -f "$CLI" && ! -L "$CLI" && -x "$CLI" ]] || fail "executable CLI not produced at $CLI"
[[ -f "$EMBEDDED_CLI" && ! -L "$EMBEDDED_CLI" && -x "$EMBEDDED_CLI" ]] \
  || fail "embedded executable CLI not produced at $EMBEDDED_CLI"
record "public CLI: $CLI_NAME (scheme $CLI_SCHEME)"
record "embedded CLI: Contents/MacOS/mostlytext-cli"
record "CLI installation: embedded app helper or explicit user-created symlink"
record "version: $(defaults read "$APP/Contents/Info" CFBundleShortVersionString) ($(defaults read "$APP/Contents/Info" CFBundleVersion))"
record "bundle id: $(defaults read "$APP/Contents/Info" CFBundleIdentifier)"

# ---------------------------------------------------------------- 3. sign-check
# Xcode signs the app, its nested code and the CLI from the build settings
# above. SwiftPM code is linked statically; its resource bundles hold data,
# not code. Check every Mach-O binary rather than re-signing blindly.
step "Check signatures"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee "$EVIDENCE/codesign-verify-app.txt"
codesign --verify --strict --verbose=2 "$CLI" 2>&1 | tee "$EVIDENCE/codesign-verify-cli.txt"
codesign -dvvv --entitlements - "$APP" > "$EVIDENCE/codesign-display-app.txt" 2>&1
codesign -dvvv "$CLI" > "$EVIDENCE/codesign-display-cli.txt" 2>&1
: > "$EVIDENCE/macho-signatures.txt"
while IFS= read -r -d '' binary; do
  file -b "$binary" | grep -q 'Mach-O' || continue
  info="$(codesign -dvv "$binary" 2>&1 || true)"
  rel="${binary#"$OUT"/}"
  rel="${rel#"$PRODUCTS"/}"
  grep -q "Authority=Developer ID Application: .*($TEAM_ID)" <<<"$info" || fail "$rel is not signed with the Developer ID identity"
  grep -q 'Timestamp=' <<<"$info" || fail "$rel has no secure timestamp"
  grep -Eq 'flags=0x[0-9a-f]+\(.*runtime' <<<"$info" || fail "$rel lacks the hardened runtime"
  echo "ok  $rel" >> "$EVIDENCE/macho-signatures.txt"
done < <(find "$APP" "$CLI" -type f -print0)
record "mach-o binaries checked: $(wc -l < "$EVIDENCE/macho-signatures.txt" | tr -d ' ')"

# ---------------------------------------------------------------- 4. licences
# Before anything is sent to Apple: the built app must match the licence
# inventory's artifact contract (runtime resources, notices, licence) and all
# release rules. Stapling later adds only the notarisation ticket, which
# doesn't change these resources.
step "Licence gate against the built app"
if python3 "$REPO/compliance/tools/compliance.py" check --release --artifact "$APP" \
     > "$EVIDENCE/compliance-artifact.txt" 2>&1; then
  record "licence gate: passed"
else
  record "licence gate: $(grep -c '^FAIL:' "$EVIDENCE/compliance-artifact.txt" || true) failure(s), see compliance-artifact.txt"
  gate "licence gate (compliance.py check --release --artifact) failed; see compliance-artifact.txt"
fi

# ---------------------------------------------------------------- 5. notarise
notarise() {  # $1 file to submit, $2 evidence name
  local id status fields submit_status=0 log_status=0
  local response="$EVIDENCE/notary-$2-submit.json"
  # Capture before testing the exit: a rejected/failed wait can still return
  # a submission identity whose diagnostic log must be retained.
  if xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json \
      > "$response" 2> "$EVIDENCE/notary-$2-submit.stderr"; then
    submit_status=0
  else
    submit_status=$?
  fi
  printf '%s\n' "$submit_status" > "$EVIDENCE/notary-$2-submit.exitcode"
  record "notarisation submit $2: exit $submit_status"
  if fields="$(python3 - "$response" 2> "$EVIDENCE/notary-$2-response.stderr" <<'PY'
import json, math, re, sys

def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate response key")
        result[key] = value
    return result

def finite(value):
    raise ValueError("nonfinite response value")

def finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("nonfinite response number")
    return number

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        value = json.load(handle, object_pairs_hook=unique, parse_constant=finite, parse_float=finite_float)
    if not isinstance(value, dict):
        raise ValueError("response is not an object")
    identity, status = value.get("id"), value.get("status")
    if not isinstance(identity, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,127}", identity):
        raise ValueError("missing or unsafe submission identity")
    if not isinstance(status, str) or not re.fullmatch(r"[A-Za-z][A-Za-z ]{0,63}", status):
        raise ValueError("missing or unsafe submission status")
    print(identity + "\t" + status)
except (OSError, ValueError) as error:
    print("Invalid notarization response: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
)"; then
    IFS=$'\t' read -r id status <<< "$fields"
  else
    fail "invalid notarisation response for $2 (submit exit $submit_status); see notary-$2-submit.json, .stderr, .exitcode and notary-$2-response.stderr"
  fi
  record "notarisation $2: $id $status"
  # Fetch Apple's log before judging the status: it explains a rejection.
  local log_ok=1
  if xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$EVIDENCE/notary-$2-log.json" \
      2> "$EVIDENCE/notary-$2-log.stderr"; then
    record "notarisation log $2: captured"
  else
    log_status=$?
    log_ok=0
    record "notarisation log $2: NOT captured"
  fi
  printf '%s\n' "$log_status" > "$EVIDENCE/notary-$2-log.exitcode"
  [[ "$status" == "Accepted" ]] || fail "notarisation of $2 returned '$status' (submit exit $submit_status); see notary-$2-log.json and notary-$2-submit.json"
  (( submit_status == 0 )) || fail "notarisation submission command failed for $2 (exit $submit_status); see notary-$2-submit.json, .stderr and .exitcode"
  (( log_ok )) || gate "the notarisation log for $2 ($id) could not be downloaded"
}
step "Notarise the app"
ditto -c -k --keepParent "$APP" "$OUT/$APP_ARCHIVE_NAME"
notarise "$OUT/$APP_ARCHIVE_NAME" app
xcrun stapler staple "$APP"
# The app's notarised bytes already include mostlytext-cli. Its public mostlytext
# command is an explicit user-created symlink to that embedded helper. A copied
# standalone binary cannot locate its containing app and is not distributed.

# ---------------------------------------------------------------- 6. dmg
VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
if [[ "$MODE" == "release-candidate" ]]; then
  DMG="$OUT/$APP_NAME-$VERSION-$BUILD.dmg"
else
  DMG="$OUT/$APP_NAME-$VERSION-$BUILD-dryrun.dmg"
fi
step "Build the DMG"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
step "Notarise the DMG"
notarise "$DMG" dmg
xcrun stapler staple "$DMG"

# ---------------------------------------------------------------- 7. verify
step "Verify"
{
  echo "## stapler validate app";  xcrun stapler validate "$APP"
  echo "## stapler validate dmg";  xcrun stapler validate "$DMG"
  echo "## spctl exec (app)";      spctl --assess --type execute --verbose=4 "$APP"
  echo "## spctl open (dmg)";      spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
  echo "## codesign verify (dmg)"; codesign --verify --verbose=2 "$DMG"
  if command -v syspolicy_check >/dev/null; then
    echo "## syspolicy_check distribution"; syspolicy_check distribution "$APP"
  fi
} 2>&1 | tee "$EVIDENCE/verify.txt"

step "Hashes"
# The DMG is the distributable. Retain the notarisation vehicle, separate
# build product and actual embedded helper hashes as non-distributed evidence.
{
  shasum -a 256 "$DMG"
  echo "# not distributed: notarisation vehicle, compiled CLI and embedded helper"
  shasum -a 256 "$OUT/$APP_ARCHIVE_NAME" "$CLI" "$EMBEDDED_CLI"
} | tee "$EVIDENCE/SHA256SUMS"

echo
echo "Done ($MODE). DMG: $DMG"
if [[ "$MODE" == "dry-run" ]] && grep -q '^UNVERIFIED' "$EVIDENCE/summary.txt"; then
  echo "Dry run recorded UNVERIFIED items (see summary.txt). This output is not a release."
fi
echo "Evidence: $EVIDENCE (contains no secrets; review before committing)"

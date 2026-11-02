# Offer the reviewed legacy editor preferences before ordinary startup

## Owner summary

On ordinary launch, MostlyText recovers a previously consented editor import before constructing mutable settings, themes or document/session owners. When original MacDown preferences exist, it offers the three exact Boolean mappings and a font only when the existing family resolver reproduces the installed PostScript face and size exactly. Each offered replacement is unchecked and explicitly names that it replaces a saved value. Continue without importing keeps normal editing available and suppresses the same source offer on later launches. Source preferences, legacy custom styles and existing MostlyText theme selections remain untouched.

## Baseline and reconciliation

Master remains `15c0fae22f7618e94c82681227057c66011be2a9`; this authorized integration change starts at `ce6273f4a7221561428e1032bc5968a4402e995e`. #557 supplies the restricted journal/bootstrap executor; #558 protects canonical sessions; #561 supplies durable stdin. This adds production optional original-MacDown import, not whole-install identity migration, signing or owner/native acceptance. The old General settings detection-only message must be replaced. No dependency or persisted font schema changes are required.

## Ownership, state and trust

AppSettings owns the bounded immutable font decision, consent selection, journal extension and startup state. The app owns installed NSFont resolution and the startup presentation. Extend the retained journal mapping only when a font is selected; continue reading exact version-1 Boolean records. Before publication, require a fresh source digest and a fresh exact font resolution. Acknowledged transactions preserve later edits even if fonts disappear. Existing journal validation and failure retention stay intact.

Startup progresses inspecting -> review -> running -> ready, or blocked on source/record/conflict/I/O errors. Blocked optional import may be deliberately skipped for this session; its files and conflicting bytes survive. Only ready permits constructing normal mutable models and starting restoration, open/reopen events, theme menus, Settings or the command receiver. Queue startup file requests and reopen demand until ready. App/UI-test hosts bypass real-domain import; their existing isolation is unchanged. Quit during inspection/running is refused until that bounded operation settles. Review/blocked states may quit immediately without a session publisher; normal safe termination begins only after ordinary owners exist. No application launch is performed locally.

The journal is a private child of the user's physical Application Support directory, named with the current product bundle identity. Existing directory/lock validation rejects symlinks, unsafe ownership/modes/granting ACLs and unsupported ownership/sync. Hold its lock through the import and close it before ordinary startup. Check for a running original MacDown before reading/replaying its source, and again at the final source callback. No process is killed. Source is read from its persistent domain only and never registered/initialized through the legacy application. One retained transaction permits one consented import; completion prevents later automatic reimport.

## Font and theme semantics

Resolve the legacy PostScript name at its stored size, obtain its installed family, and resolve that family through the same no-trait/weight-5 path the normal editor uses. Offer the font only if PostScript identity and point size agree exactly. Missing, substituted and nonrepresentable faces are reported and never guessed/downloaded. Destination fonts already present require explicit replacement just like Boolean values. Revalidate after consent and before a first write.

Legacy editor styles are PEG/attribute-based highlighting definitions, while MostlyText themes use semantic captures and additional chrome/preview roles. A shared display name is insufficient evidence of exact compatibility. There are no reviewed exact aliases; all legacy style names, including custom and Tomorrow names, stay explicitly unsupported and current theme slots/appearance/custom files survive. Explain this in the offer and bind that disposition in the executable report/JSON record. This is a completed conservative disposition, not a new style converter.

## Concurrency, failure and limits

MainActor serializes consent/state/publication. Journal I/O stays with its existing actor; source admission retains the 1 MiB/2,048-entry/depth/string limits. Stale consent, concurrent source app, changed source, destination or font, invalid/future journal and storage failures block import with localized recovery copy, no preference rollback and no deleted stages. No settings owner exists during those awaits. Overlapping begin/apply/continue calls cannot bypass a running operation. Cancellation leaves journal recovery available. The dismissal digest is only an offer preference, not acknowledgement; its write is checked and does not overwrite a malformed existing marker.

## Verification and slices

1. Add exact font decisions and font-aware, backwards-compatible journal replay. Test missing/substituted/face/size disagreement, explicit replacement, unselected preservation, restart/revert and changed installed resolution with synthetic data.
2. Add injectable startup controller and production barrier/presentation. Test no writers before ready, stale consent/source/concurrent legacy process, ignored source, complete journal, conflict/skip, overlapping operations and storage errors in disposable internal-disk directories and unique defaults suites.
3. Run focused Debug/Release non-GUI harnesses, strict format/lint, Compliance, local build-for-testing only, and full hosted package/app/Debug/Release/pin checks. Self-review exact source, merge integration-final only after green checks and actual-tree proof, update #53/#18/#183. Native UI/VoiceOver, real legacy domain, whole-install migration, final localization and signed-artifact gates remain open.

All new user copy belongs to Localizable.xcstrings before final localization. The startup offer provides labels, explicit buttons and keyboard navigation through standard SwiftUI controls. Markdown document bytes and export behavior do not change. No Daybreak, test-account credential, public release or original-app execution is required.

## Local evidence before hosted CI

The source-bound non-application harness passes all 150 tests in 23 suites in Debug and Release, including the two actual installed-font controls. It compiles AppSettings/JSONSupport and only the app's font/environment helper; AppDelegate, application entry point and document windows are absent. Fixtures use unique synthetic preference suites and private internal-disk directories. New coverage includes explicit selection/readiness, source drift, a suspended inspection that cannot be skipped, invalid journal retention, test-host bypass, font-only consent/recovery and exact preservation of unselected Unicode font names.

Strict SwiftLint and SwiftFormat pass. All 97 Compliance tool tests pass. Initial failures are retained: a throwing Swift Testing macro expression was precomputed, the mutable source fixture now has an isolated owner, long localized copy and the delegate body were split to meet existing lint limits, and the first generated-project compile missed a moved launch-argument source until XcodeGen was regenerated. Final app/test compilation is compile-only; it does not establish native UI or owner acceptance. Logs and source hashes are retained under `CORTANA-Builds/production-migration-20261102`. Full hosted results and exact merge/source proof are recorded in the PR and issues after they complete.

The pinned original `Tomorrow.style` uses `H1`, `EMPH`, `LIST_BULLET` and other legacy style roles with its own colors/font traits. This is not the current semantic theme schema and no name-only alias is installed. The source was inspected at `MacDownApp/macdown@3e2a2bf101c215c143bf00d9f857965f0ee82487`; original preferences resolve their stored font with `NSFont fontWithName:size:` at `MPPreferences.m:144–147`.

# Preserve authoritative sessions during bootstrap

## Owner summary

Distinguish a missing session from one that is corrupt, newer or only partly
readable. Restore readable tabs where possible, preserve the original bytes,
and refuse an autosave that would erase state this build cannot represent.
Expose this inspection to the application bootstrap barrier. Existing Quit
recovery reporting consumes a failed verified save instead of claiming success.

Baseline: master `15c0fae22f7618e94c82681227057c66011be2a9`, integration
`7e9ace58a38d96a922c1d482eb78b3b0f371925b`, stacked with #557's editor journal.
Current `loadSession()` salvages readable tabs and makes an unreadable copy,
but ordinary save replaces the primary regardless of decode loss or version.
The optional loader is not sufficient bootstrap admission evidence.

## Admission and publication

Add pure `WorkspaceSessionAdmission` classification for absent, readable,
partially readable, unsupported and unreadable/oversized bytes. Use the existing
JSONSupport duplicate-safe bounded-depth parser before decoding: exact version-1
integer spelling, known root/tab keys, unique tab IDs and complete typed decode
are required for a writable current session. Partial salvage remains readable
for existing restoration, but cannot authorize dropping unknown/lost data.
Workspace gains only the acyclic Foundation-only JSONSupport dependency.

The file adapter reads at most 16 MiB through a nonblocking no-follow descriptor,
requires a single-link owned regular file, and checks identity/size/timestamps
and the named object around the read. A verified snapshot carries the actual
FileCore revision. Writes use FileCore's existing conditional publication (or
exclusive absent-destination publication), so an external replacement after
admission is preserved. Existing volume-specific FileCore conditional-publication
limits remain explicit; this does not invent a cross-process transaction.

`saveSessionVerified` becomes a protocol requirement with its existing default
for other stores. The real file store returns true only after conditional write
and exact admitted-byte readback. This prevents existential callers from using
the old optional-loader equality fallback to acknowledge a refused write.
Unreadable backup creation is exclusive and 0600; it never deletes/replaces an
older backup. No malformed/future/partial primary is rewritten or removed.

All operations retain the current MainActor owner; there is no new await between
inspection and write. This unit adds no UI, app launch, identity change, automatic
reset or legacy-domain access. It supplies bootstrap admission and immediate
ordinary-store no-clobber behavior; whole-install migration and the startup UI
barrier still consume this API in subsequent work.

## Verification

Exercise valid historical/current sessions, corrupt/future/duplicate/unknown
fields, partial tab loss, repeated ordinary saves, exact verified acknowledgement
through a protocol existential, an external replacement before publication,
absence races, first-backup preservation, symlink/hardlink/nonregular/oversized
files and exact bookmark/recovery identities. Use only disposable fixture files.
Run focused Debug/Release controls, strict lint/format, Compliance, full hosted
package/app tests and Debug/Release builds before merging into integration-final.
Passing storage tests does not establish native restore/migration acceptance.

Focused local verification: all 19 tests in the three session-store/admission
suites pass in Debug and Release, including the existing historical/salvage
controls and six new publication/safety controls. Self-review added nested
encoding/syntax key coverage and an admitted nested-future-field regression;
partial loader equality cannot acknowledge a refused save through a protocol
existential. Strict lint/format and ordinary Compliance pass. The first harness
omitted the existing Fakes helper; that setup failure is retained with corrected
runs in `CORTANA-Builds/session-bootstrap-20261102`. No application or real
session directory was opened; full hosted regression/build checks follow.

## Hosted verification correction

The first hosted run passed all 3,122 package tests (426 suites, two existing
Neon known issues) and app/CLI Debug/Release builds, but build-for-testing
failed to link JSONAnalysisStore symbols. The app and app test sources directly
import JSONSupport while the project spec relied on transitive linkage. Declare
the existing JSONSupport product for both targets; no dependency version changes
or test exclusions. Retain the first run and require a full corrected run.

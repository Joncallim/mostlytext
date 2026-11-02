# Recover a consented editor migration after interruption

## Owner summary

Record the exact approved editor change before publishing it, then retain durable
acknowledgement and completion records. Startup can resume an interrupted change
without reimporting over later edits. This implements the journal and its
bootstrap executor for the three reviewed Boolean conversions; the complete
identity/session/theme migration and consent UI remain separate E17 work.

Baseline: master `15c0fae22f7618e94c82681227057c66011be2a9`, integration
`7e9ace58a38d96a922c1d482eb78b3b0f371925b`. Reuse #555's synchronous MainActor
settings publisher. No dependency, identity, source-domain or native-account
change is needed. The journal lives in AppSettings and imports Foundation,
Darwin, CryptoKit and the existing JSONSupport module only.

## Storage and trust

The caller supplies a trusted, physical managed journal directory. Open its
parent without following symlinks, create only its final component with 0700,
and require owned 0700/no-grant-ACL storage on an ownership-enforcing volume.
Hold an owned regular single-link 0600 advisory-lock file for the journal's
lifetime. Revalidate named directory/lock identity and permissions on every
operation. Never unlink lock, directory, unknown files or failed staging files.
This coordinates participating processes; it does not authenticate hostile
same-user code.

Use immutable `plan.json`, `acknowledged.json`, and `complete.json` files. Each
write uses an exclusive random 0600 stage, bounded writes, fsync and
F_FULLFSYNC, exclusive rename and directory fsync. Existing identical records
are revalidated/resynced; differing records are preserved as conflicts. Failure
can leave a private stage or a published record, which the next inspection
classifies. No failure means success by inference. Directory/file replacement,
symlink/hardlink, granting ACL, unsafe mode, unsupported sync or I/O errors
stop execution without preference publication/completion.

The plan is canonical, duplicate-free versioned JSON, at most 256 KiB. Bind its
transaction UUID, exact destination domain, source digest, mapping version,
before bytes (or proven absence), desired bytes and selected fields. Editor
blobs are at most 64 KiB each. Recovery validates strict settings admission,
digests, selected fields and preservation of every unselected setting. Marker
records bind the exact plan digest and phase. Corrupt/future/unknown records are
retained and block automatic recovery. No preference values enter public logs.

## State, ownership and cancellation

An actor owns filesystem work. A MainActor bootstrap executor owns the existing
settings store and rejects overlapping operations while awaiting the journal.
Start captures authoritative before bytes and durably prepares the plan; after
that await, obtain a fresh source through the supplied callback and recheck the
destination at the ordinary publisher boundary. No await separates that final
comparison, setting and exact saved-byte readback. Cancellation before the write
leaves a resumable prepared plan. After successful readback, finish recording
acknowledgement/completion even if cancellation was requested.

On restart, prepared + desired bytes means acknowledge without rewriting;
prepared + before bytes allows the original planned write with a matching fresh
source; a third value is a preserved conflict. A durable acknowledgement proves
the intended single-domain write was read back: later edits, including a revert
to the before value, survive and must never be reapplied. Complete records are
historical success and do not require the user to keep the imported values.
A different proposed transaction cannot silently replace the retained plan.
Destination-domain mismatch always blocks. Readback does not make UserDefaults
a disk-durable multi-key transaction; retaining the plan/source enables recovery.

No original preference domain is read by this executor: the host supplies the
bounded fresh source snapshot. Normal safe editing remains available after an
optional-import conflict. The executor exposes empty/prepared/acknowledged/
complete inspection and ready/conflict/recovery-required outcomes to a future
application startup barrier; it does not activate first-run import by itself.

## Verification and completion

Use disposable internal-disk directories and unique synthetic defaults suites.
Exercise each durable boundary, process-owner contention/reopen, interrupted
prepare/publication/ack/completion, unknown/future/malformed records, source drift,
destination drift during preparation, later edits/reverts, domain mismatch,
cancellation, failed readback, unsafe storage, file replacements and idempotence.
Run focused Debug/Release tests, strict lint/format, Compliance and full hosted
package/app/Release/lock checks before merge. Native and whole-install migration
acceptance remain open; no journal file is written into the owner's real stores.

Local verification: all 135 AppSettings tests in 20 suites pass in Debug and
Release, including 20 new journal/bootstrap controls and twelve injected
write-boundary interruptions. Source hashes match the copied Foundation-only
harness. Strict lint/format and ordinary Compliance pass. The first compilation
exposed a throwing Swift Testing macro inference issue; explicit reads fix it.
The first runtime failure expected indentation 9 even though the existing model
clamps it to 8; the fixture now uses an admitted nondefault value. Unavailable
UserDefaults Sendable conformances were removed from new/adjacent test doubles,
with warning-free final builds. Self-review added record-identity/readback checks
after sync and after publication, plus a replacement regression. All initial and
corrected logs are retained in `CORTANA-Builds/migration-journal-20261102`.
Full hosted CI and source review remain required before integration.

# Preserve changed staging files after a failed save

## Owner outcome and baseline

A failed save must not delete another writer's bytes. A private Foundation/POSIX
review of source 0392af7a reproduced four actual failures: both ordinary and
conditional saves blindly deleted a sibling stage after an in-place edit or
replacement. The destination remained intact, but the changed stage was lost.
Master is now 87d8d48b after #578, integration-final is cf3f8b86. Its FileCore
source is byte-identical to the reviewed 0392af7a source. Repeating the private
controls against all 54 exact merged FileCore/JSONSupport source/resources
reproduces the same four failures, with 126 other tests passing. This remediation
is based directly on merged master, independent of pending #570–#577. Existing
release/native gates remain binding.

## Narrow architecture

FileCore owns an internal staging object with a directory descriptor, an
exclusively created regular-file descriptor, and a receipt derived from the
known encoded bytes plus the created object's identity and metadata. No new
module dependency or public error case is introduced. Existing conditional
recovery errors also carry a preserved competing staging file's location;
callers already keep the document dirty and offer Reveal/Save As.

Create the stage with exclusive/no-follow POSIX open, write the known bytes,
verify the created descriptor and name, and retain its handle until publication
ends. After carrying destination metadata, update the receipt only through the
same created descriptor and verify known bytes before using it. Preserve partial
or unverified stages on an error; inability to establish a receipt never grants
cleanup authority.

Failed-save cleanup may remove only a stage still matching its receipt. Move
that named object to a fresh sibling quarantine with no-replace rename, then
verify regular type, original identity/size/permissions/owner/link/flags/birth
and modification times and the complete SHA-256 through a bounded 64 KiB
no-follow descriptor read. Bracket reads with full metadata/name checks. Rename
changes ctime, so compare it within each stable observation, not across rename.
If anything differs, restore without replacing a new occupant or preserve the
quarantine and report its recovery URL. If the stage is already absent there is
nothing to remove. Unsupported quarantine rename conservatively retains it.

This is a failed-save cleanup repair. The existing conditional publication and
its successful displaced-baseline retirement remain separately reviewed code;
this change does not claim a hostile same-UID filesystem compare-and-swap,
crash journal, automatic scavenger, or release/native acceptance.

## Verification and stop conditions

Keep the original four failing controls. Add unchanged-stage cleanup, same-byte
replacement, metadata-only/in-place mutation, symlink/FIFO substitution and
quarantine mutation/occupied restoration controls using private fixture roots.
Exercise ordinary/conditional saves, baseline refusal, rollback, FAT32 fallback,
permissions/ACL/xattrs, and encoding/BOM through existing source tests. Run Debug
and Release source harnesses, strict lint/format, project regeneration/pinning
and compile-only integration. Full hosted checks must pass before merge. Do not
weaken timing ceilings or bookmark authority to accommodate hosted failures.

## Observed source verification

The repaired FileCore plus the merged-master JSONSupport dependency passes 134
source tests in 18 suites (including parameterized substitutions) in Debug and
Release. The initial wider harness compile missed existing shared prober/watcher
support; adding the exact existing support file fixed that harness setup error.
The initial lint found complexity 11 in writeLocked; factoring error retirement
restored the existing limit without changing the gate. Final strict lint has zero
violations. XcodeGen regeneration, committed package pins and unsigned Debug
build-for-testing passed; no product or UI tests were executed locally. Existing
Diagrams/DiagramsD2 dependency-scan warnings are retained separately for review.
No full hosted pass for this remediation is claimed yet.

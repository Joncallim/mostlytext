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

## Review extension: successful displaced-baseline retirement

A second post-main control now reproduces the analogous race after a conditional
save verifies the displaced old baseline: replacing or editing that temporary
object before removal destroys the new bytes and incorrectly reports success.
Two cases each fail both their error and retained-byte assertions. The test seam
runs exactly between successful verification and the existing remove operation.

Extend the same narrow FileCore retirement mechanism to the approved displaced
baseline. Capture no-follow metadata, require the caller-approved baseline's
identity/size/modification time and complete known SHA-256, then bracket its
streamed verification with metadata/name checks. Return an in-memory retirement
receipt. Run the existing after-verification control before receipt retirement;
changed objects must survive and report recovery, while the published document
is never falsely accepted. Reuse the exact quarantine/restore implementation
for owned stages and approved displaced baselines. A pathname or same-byte
replacement cannot mint authority. No new persistence, module or public error
is introduced. Retain both original negative controls and existing rollback,
FAT32, metadata and encoding assertions.

The shared retirement implementation initially reconstructed Foundation dates
from stat nanoseconds; double rounding caused eleven real test issues. It now
uses the exact Foundation metadata conversion used by FileRevision, bracketed
by the existing full no-follow metadata/name checks. No tolerance or assertion
was weakened. All 135 source tests in 18 suites now pass in Debug and Release,
including both after-verification mutation/replacement cases. The rebased
compile initially retained a generated project from the larger pending stack;
regenerating/pinning the project removed missing-input errors and the exact
master-based app/test targets then compiled successfully. Keep those initial
setup and implementation failures in the evidence ledger.

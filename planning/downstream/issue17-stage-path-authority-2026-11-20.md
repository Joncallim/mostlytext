# Bind save publication to the opened staging directory

## Owner summary

A save prepares its new bytes in a private folder beside the destination. The
folder is opened and checked, but the earlier publisher reopened its pathname.
If that folder name was replaced between the check and exchange, a different
file could briefly become the document before rollback. The save path now uses
the already opened folder and destination-parent handles to create, inspect
and publish its stage. The same binding covers conditional saves, absent-file
Save As, and ordinary replacement.

This is a source-level fix for issue #17. It does not establish the deferred
cross-account native privacy or whole external-file lifecycle matrix.

## Observed failure and repair

- Base: MostlyText `main` `c069cf636fc8ba768b5b186d2e0e8626654a54ff`.
  A controlled `afterBaselineVerification` interleaving moved the private
  folder and substituted a symlink to a second folder containing `stage` with
  different bytes. At the existing displaced-read seam, the destination
  contained the substituted `attacker bytes`. The old rollback later restored
  the original, but another reader could observe the wrong content in between.
  The retained base run is `/private/tmp/mostlytext-stage-path-before.log`,
  SHA-256 `3d3354bd13e8b22266fef13908ab3cf8ce630a8c11f993a2570d03ac7c308ac6`.
- `FileStoreStage` creates bytes relative to a duplicate of the verified
  private-directory descriptor. Metadata is copied between open file
  descriptors. Exchange, rollback, recovery preservation, exclusive Save As
  and ordinary replacement use directory-relative operations. The publisher
  also rejects a private directory whose original name no longer refers to
  the opened object before publication.
- A second controlled interleaving swaps the folder name **after** that final
  name check. The destination receives the original staged bytes through the
  open descriptor, while the substituted folder's bytes remain untouched. New
  and existing destinations exercise the same late boundary. Direct stage
  creation is also checked after a folder rename.
- On a volume without exclusive rename, an absent-destination Save As now
  fails closed. The previous path-based fallback checked absence separately
  from a move and could not prove that another writer had not won. Existing
  conditional saves on volumes without exchange retain their documented
  baseline check and atomic rename fallback.

## Verification and limits

The first focused test failed on base and passed with the repair. A clean
Debug build passed 149 selected FileStore, FileDocument and Workspace save
tests in 19 suites. The same optimized Release selection passed 149 tests in
19 suites. Final-source logs are
`/private/tmp/mostlytext-stage-authority-frozen-debug.log` (SHA-256
`4290e3b19c1f80e2f66df866173d08fb30cee6ee22f507f84a556abb0e3d3a57`)
and `/private/tmp/mostlytext-stage-authority-frozen-release.log` (SHA-256
`3f4c13baabe94868ff75636ca782a35fcc1981c706298878bf03cd689e5a69b7`).
The first combined Debug attempt and isolated Workspace selection
exited with signal 11 after an incremental build changed `FileStore`'s layout;
the exact base test passed and a clean branch rebuild passed both the exact
test and combined selection. The first failures remain in
`/private/tmp/mostlytext-stage-authority-debug.log` and
`/private/tmp/mostlytext-workspacemodelsave-isolated.log`.

Ordinary source compliance passes; strict release compliance retains ten
existing #14 rights/source-location failures. Source-format and lint checks
pass on the changed files. Hosted locked builds, app-level save/controller checks and
review remain to be recorded against the final PR head.

Directory-relative operations protect the prepared bytes from substitution of
the private folder name. A concurrent rename of the destination's ancestor,
filesystems that do not enforce POSIX permissions, cross-account denial and
the exact native candidate are separate #17/#12 acceptance boundaries. The
original issue checkboxes remain open until their full criteria are proved.

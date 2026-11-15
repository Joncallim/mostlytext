# Newer external revision during conflict resolution — 16 November 2026

## Owner summary

When the user chooses Use Disk Version, MostlyText first removes the old
recovery record. That asynchronous cleanup gives the file watcher time to
observe another disk edit. If local text and the conflict state are unchanged,
the current completion can install the older snapshot over the newer conflict.
The editor should retain the local draft and the latest disk conflict so the
user can choose again against current bytes.

## Current architecture and repair

`ExternalFileController.applyConflictResolution` owns the choice, recovery
cleanup and final model/editor publication. `FileDocument` carries the bound
URL, recovery lifetime, last accepted revision, pending external revision and
backing state. The existing post-cleanup guard checks only lifetime, text and
state. Keep this ownership path and require the same bound URL and disk
authority on return. Do not use `mutationGeneration` alone: harmless monitor
metadata transitions can advance it without changing the choice's source.

An older cleanup may have removed the recovery record. On a superseded choice,
the existing path must persist the current dirty/conflicted document again.
No file bytes are written by this repair, and no watcher policy changes.

## Verification and boundary

Add a controlled disk-backed interleaving that observes a second external
revision during the held cleanup. It must fail against the current guard,
then pass with the old choice rejected, local text retained, the newest
pending revision retained and newest disk bytes untouched. Run the existing
edit, tab-switch, recovery-lifetime and disposal controls, the seven external
controller matrix tests, complete CI and optimized Release checks.

The automated result does not close #12's interactive matrix, whole-process
idle-wakeup requirement or formal candidate gate. It does not establish #19's
historical parser trigger or #18's 50 ms full-path budget.

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
The initial monitor-snapshot await is also checked against the exact recovery
lifetime, last known revision, backing and encoding. A rotated lifetime with
the same URL, text and conflict state cannot inherit an earlier choice.

An older cleanup may remove recovery at the same mutation version as the
newer live draft. On a superseded choice, find the captured tab and recovery
lifetime even if the tab became inactive, advance its recovery version above
the removal fence, then persist its exact current text. A closed or rebound
tab is not resurrected. A failed persist for a retained inactive draft keeps
its retry action and warning; a successful persist of another tab must not
clear that retry. The extra version invalidates stale generation-keyed work
without touching editor text, selection or paint. No disk document bytes are
written by this repair, and no watcher policy changes.

On the accepted path, a stale versioned recovery removal can return
`alreadyAbsent` even while a newer recovery file exists. Reload-specific
cleanup verifies actual absence inside the recovery actor before publishing
clean state. A newer recovery record blocks the choice and retains the local
conflict. One metadata-only generation advance remains admissible, as
required by the existing conflict-close behavior; repeated advances require
a fresh choice against current state.

## Verification and boundary

Add a controlled disk-backed interleaving that observes a second external
revision during the held cleanup. It must fail against the current guard,
then pass with the old choice rejected, local text retained, the newest
pending revision retained, newest disk bytes untouched and the draft
loadable from its recovery file after the queue drains. Cover a newer recovery
file, a recovery-lifetime rotation during the first snapshot await, an inactive
dirty tab, a failed persist and cross-tab retry ordering. Run the existing
edit, tab-switch, recovery-lifetime and disposal controls, the seven external
controller matrix tests, complete CI and optimized Release checks.

The automated result does not close #12's interactive matrix, whole-process
idle-wakeup requirement or formal candidate gate. It does not establish #19's
historical parser trigger or #18's 50 ms full-path budget.

## Preserved first hosted failure

The focused Debug run at test commit `b2d981fec11f4eab02bb87e4b566e4aeab0add70`
([run 43742155894](https://github.com/Joncallim/mostlytext/actions/runs/43742155894))
compiled the actual app and executed 16 tests in four suites. The two new
durability assertions failed: an edit during cleanup and a newer external
revision both left the retained draft absent from recovery. The downloaded
`/private/tmp/mostlytext-pr284-red-debug/latency.log` has SHA-256
`85a748c115f37f823a694a1ef524b22ee48b2304d31196ae5e17957e21cfcb9c`.
This is a real failing-before product result, not a successful retry or an
unrelated build failure. The run artifact retains its result bundle. Final
source checks are recorded only after the repair is frozen.

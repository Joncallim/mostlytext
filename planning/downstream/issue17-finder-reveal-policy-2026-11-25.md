# Finder reveal replaces sidebar Trash

## Owner summary

The folder sidebar previously offered **Move to Trash**. Its final Foundation
call accepted a pathname after root validation, so a folder could be redirected
between the check and deletion. The owner chose **Reveal in Finder** for this
pass. The app now hands the selected item to Finder and offers no
in-app Trash operation. Finder owns any later deletion and recovery action.

The Folder menu uses the same wording. Its old Command-Delete binding is gone,
so that keystroke remains available to text editing. The context-menu action
and Folder command check that the selected URL is still lexically under the
current folder root before asking Finder to select it. This is a UI guard, not
a claim that Finder receives descriptor-bound authority.

## Scope and source disposition

- Remove both user-facing Trash entries, the confirmation sheet and the
  `FileTreeModel.moveToTrash` / `FileTreeMutation.trash` / `FileSystemMutator.trash`
  route. No production file-tree code calls `FileManager.trashItem`.
- Keep existing rooted create, rename, move and copy behavior and its tests.
  Existing external-file deletion detection remains separate.
- Reuse the existing **Reveal in Finder** catalog key. Remove three obsolete
  Trash prompt keys and refresh the source-bound plain-string and catalog
  inventories. Historical receipts and earlier failed probes remain intact.
- The pre-existing `documentFileWasDeleted` recovery helper remains in source
  but has no UI caller after this policy change. It cannot initiate deletion.

## Verification and limits

The focused FileTree package selection passed 90 tests in nine suites. The
locked Debug app and UI test bundles compiled without launching the app.
Changed-file SwiftFormat and strict SwiftLint, the reviewed string-sink guard,
catalog inventory and ordinary compliance passed. Strict release compliance
retains the ten existing issue #14 provenance/publication failures.

The updated sidebar UI test verifies the visible Reveal item and absence of
the old Trash action; it is compiled but awaits the owner-deferred protected
native checkpoint for execution. At that checkpoint, confirm Finder selects the
intended file or folder, no app-owned delete/confirmation appears, and normal
text Command-Delete behavior is preserved. This source change alone does not
complete issue #17's whole native and final-candidate audit criteria.

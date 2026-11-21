# Keep workspace search current while the window remains open

## Owner summary

Quick Open and Folder Search already share an in-memory index. They followed
MostlyText's own file operations and rebuilt when a window became active, but
an edit by another program inside a nested folder could leave the visible
window's index stale indefinitely. This change gives each open workspace one
recursive macOS filesystem event stream. A short delay combines bursts of
events into one rebuild. A moved or replaced selected root retires actionable
results before the next walk.

The stream reports only that something changed. It does not provide new file
authority, read contents, or run a disk walk for every search keystroke. An
unavailable event stream falls back to the existing activation refresh; it
does not claim live external freshness. Changes below a symlink to a directory
outside the watched physical tree may not produce a root event and remain a
limit for the final F18 disposition.

## Baseline and ownership

- Base: `c1c27b81461b606935f48b68819f9277aa969f65` on `main`.
- Issue #17 F18 owns workspace index freshness; F19 owns stale result
  admission. Issue #6 and #8 consume the final outcome but remain open.
- `WorkspaceFileIndex` continues to own the snapshot and coalesced rebuild
  cancellation. `WindowController` owns the single watcher and its lifetime,
  matching its per-window index and selected `FileTreeModel` root.
- The watcher uses the same FSEvents lifetime pattern as
  `Themes/ThemeCatalogEvents.swift`. It holds no app document or window.

## State and failure behavior

1. A root request cancels the previous stream and pending debounce before its
   first await. A successful tree-root application starts one stream for the
   selected access directory before the initial index build.
2. Each event coalesces for 250 ms. The latest event re-walks the current
   selected root; a superseded build cannot publish over a newer one.
3. Root-change events or a mismatched selected root identity immediately
   retire Quick Open and Folder Search actions. Old paths may remain privately
   cached until the next root request; they cannot be opened or replaced. A
   same-path replacement cannot revive the old result.
4. A selected-root rename performed by the app rebinds the stream to the new
   access URL when the existing mutation refresh runs.
5. Losing the folder access scope or closing the window cancels the stream and
   debounce before the tree scope is disposed. Failed stream creation leaves
   the existing activation refresh.

## Verification and remaining gates

The selected package test observes a real nested filesystem event. One app
test exercises the real stream through the production window/index path.
Other app tests inject controlled events for nested add, active Folder Search
refresh, event burst coalescing, root switch and root replacement, alongside
the existing index tests.
The reviewed plain-string ledger records the unchanged two `Untitled` sinks in
`WindowController.swift` at their shifted lines and the new file digest;
its 68 selected routes still have zero unreviewed plain exceptions. Four wider
localization areas remain deferred exactly as before.
Compile the app and tests without owner-desktop launch; run the selected app
tests on an authorized disposable hosted Mac, then the relevant Release and
whole-app gates before integration. Final signed candidate and protected native
journeys remain separate. Do not close #17 or F18 solely from source tests.

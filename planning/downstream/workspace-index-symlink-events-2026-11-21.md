# External symlink coverage for workspace search — 21 November 2026

## Scope

PR #328 established one recursive FSEvents stream for the selected physical
workspace. The index already follows directory symlinks outside that root, so
files beneath those links could be indexed without their later changes reaching
the stream. This change binds the same index walk to its physical watch set.

`DirectoryWalker` returns indexed paths and the distinct external directory
targets it entered in one result. The window installs one FSEvents stream with
the selected physical root plus those targets. A changed target causes the
same coalesced, bounded rebuild as a root change. When the set of targets
changes, the window restarts that one stream, makes the prior results inert,
and scans again under the new coverage before restoring actionable results.
The selected root and window lifetime guards from PR #328 remain in force.

Apple's [FSEventStreamCreate documentation](https://developer.apple.com/documentation/coreservices/1443980-fseventstreamcreate)
defines `pathsToWatch` as an array of hierarchy roots. Its
[WatchRoot flag](https://developer.apple.com/documentation/coreservices/kfseventstreamcreateflagwatchroot)
reports a watched root moving or being renamed. The existing stream also
requests file-level events and treats any delivery as requiring a full scan;
it does not infer correctness from individual event paths.

## Boundaries

- At most 256 distinct external symlink directory targets are admitted. A walk
  beyond that budget fails the index instead of publishing unmonitored rows.
  The existing 250,000-path and 100,000-directory walk caps remain.
- A stream that macOS cannot start retains the existing key-window refresh
  fallback. That fallback does not establish continuous external freshness.
- The private installed-app journey, 100k-path reconciliation latency and
  multi-window watcher occupancy are still separate #17/#6/#8 acceptance.
  This source change does not satisfy those rows by itself.

## Verification before hosted app execution

- Selected `DirectoryWalkerAliasTests`, `WorkspaceFileEventsTests` and
  `WorkspaceFileIndexTests`: 27 tests / three suites passed in Debug. These
  include external-target discovery, the watch-root cap and a real multi-path
  FSEvents delivery on disposable folders.
- Locked `MacDown2` build-for-testing passed after the final app test was
  added; it compiled app and UI-test bundles without launching MostlyText on
  the owner desktop.
- Strict SwiftLint, SwiftFormat, `git diff --check`, ordinary compliance and
  the 68-route plain-string sink audit pass. The reviewed sink ledger changed
  only for two unchanged localized `Untitled` routes shifted by new fields.

The app-target real external-target and late-added-symlink tests require
hosted execution on the proposed PR head. They are not claimed as local native
passes here.

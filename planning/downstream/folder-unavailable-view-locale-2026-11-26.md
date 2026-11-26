# Folder-unavailable copy follows the sidebar language

## Owner summary

When a watched folder vanishes, the sidebar can remain open with a recovery action. The watcher previously stored an already-translated message, so changing the presenting language left that message in the old language. This change stores a `rootVanished` outcome and resolves the existing FileTree catalog entry when the sidebar draws it. It leaves OS-provided unreadable-folder details verbatim and does not change root access, file bytes, recovery choices or watcher timing.

## Source and verification

- Baseline main: `33c022c79c3f76c04933f46f03dc8ff64d5e9591`. The former `FileTreeModel+TreeState.swift` watcher assigned `String(localized: "The folder is no longer available.", bundle: .module)` to `.rootUnreadable(reason:)`, and `SidebarView+Folder.swift` displayed the stored reason with `Text(verbatim:)`.
- The app's compiled FileTree resource contains `The folder is no longer available.` → `Le dossier n'est plus disponible.` in `fr.lproj`. The route resolves the package-owned resource bundle for the view locale through `ViewLocalizationBundle`.
- A source-equivalent compiled-resource control using that built FileTree bundle returned English from the former direct-bundle lookup even with a French formatting locale, and French from the selected `fr.lproj` lookup.
- The existing root-vanish test now proves the typed terminal state, notification ordering and preserved raw OS error detail. Local pinned `swift test --filter FileTreePreviewRootBoundaryTests` passed 3 tests/1 suite. The first local French assertion failed because the SwiftPM package test bundle copied `.xcstrings` raw and had no compiled `.lproj`; that first failure is retained as an evidence-boundary correction, not reported as a product regression. The French lookup assertion is in the app-target `ViewLocaleCopyTests`, which uses the compiled package bundle; local pinned app/test `build-for-testing` succeeded, but that test has not run locally.
- Strict SwiftLint and SwiftFormat, 44 localization/coverage tool tests, 15-catalog/747-entry inventory, the selected 799-source/60-sink ledger, ordinary compliance, pin verification and diff check passed. The inventory change updates one shifted source-line reference only; no catalog key or translation value changed.

The hosted final-head app test and required PR checks are separate acceptance gates whose actual results belong in the PR review. This scoped source repair does not complete issue #3's whole-app string audit, translation review, installed non-English flow, pseudo-localization or final freeze. The owner-deferred protected native checkpoint remains open.

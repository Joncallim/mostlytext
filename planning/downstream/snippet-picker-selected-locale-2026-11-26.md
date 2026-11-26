# Snippet picker uses one selected language

## Owner summary

The Insert Snippet panel can show built-in names and a file-error notice in
the process language while its SwiftUI controls use another selected language.
The panel will resolve all of its own copy when it opens, using the same
language for built-in names, notices and controls. User-authored snippet names
and insertion bodies remain literal. This is a source correction under #3;
installed language, translation review, pseudo-localized layout and final
string-freeze acceptance remain separate.

## Baseline and boundary

Baseline main is `12cbd1a62e7c600f768449e82c85b5f9c1fbb33a`. The live
`SnippetPickerPanel` receives a list and notice already resolved by
`WindowCoordinator.presentSnippetPicker`, then creates an `NSHostingView`
without an explicit locale. `BuiltInSnippets.all` uses EditorCore's bundle
with the process preference. `WindowCoordinator.snippetNotice` uses the app
bundle with that preference. The command palette already chooses the app's
preferred localization at its panel boundary and supplies that locale to its
content. The older E16 implementation note's ten-catalog count is historical;
the current catalogs and #3 govern this change.

EditorCore continues to own built-in snippet IDs, scope and bodies. It gains a
locale-selecting display-name entry point using the existing FileCore bundle
resolver; its default `all` entry remains source compatible. The app
coordinator chooses one locale before constructing a panel and resolves the
notice and names with it. The panel injects that locale into its hosted view.
This adds no persistence, new catalog key, file access or dependency direction.

## Journeys and invariants

- In a French app language, opening Insert Snippet selects the French resource
  values for built-in names, controls and file-error copy, and searches the
  displayed names. The currently shipped French catalog values for this route
  are English `needs_review` drafts; translation quality remains open.
- A user-provided name stays byte-for-byte authored, including an override of
  a built-in ID. The selected snippet inserts the same body and retains its
  existing origin-tab and undo ownership.
- A missing, unreadable, newer-version or partially usable `snippets.json`
  keeps the existing list/fallback behavior; only its notice language changes.

The panel uses a locale selected at open time. A later OS language preference
change requires reopening the panel, matching its fixed candidate-list
lifetime. No document text or disk bytes are translated or normalized.

## Verification and stop conditions

Extend the existing EditorCore multilingual fixture so explicit English and
French selection resolves distinct names without changing IDs, scopes, bodies
or user overrides. Extend app snippet-picker tests with a multilingual app
bundle for each notice outcome, then review the panel's locale injection in
source; actual panel presentation remains a native checkpoint. Run the owning
package and app suites first, then the existing selected CI lanes, catalog
inventory, selected string-sink guard, lint, format and ordinary compliance.
Do not claim native non-English or final E16 acceptance from source tests.
Stop and revise this boundary if selecting a package locale changes snippet
insertion semantics or requires an app-to-package localization dependency.

## Local result on this branch

The first package test build rejected the new explicit-locale call because the
API did not exist. After implementation, the 12-test SnippetLibrary suite
passes with English/French sentinels and unchanged insertion identity. The
first pinned app test-bundle compile found a missing `return` before the
notice switch; the corrected incremental pinned Debug `build-for-testing`
passes. This is compilation, not local app or UI execution. The 15-catalog,
747-entry structural inventory, reviewed 799-source/60-sink guard, strict
changed-file lint/format and ordinary compliance pass. The focused app test,
final-head hosted checks and actual panel presentation remain separate gates.

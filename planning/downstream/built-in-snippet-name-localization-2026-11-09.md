# Built-in snippet name localization

## Owner summary

The six built-in Markdown snippet names appeared in the picker only as English
text, even when the rest of the app used a different language. Their display
names now resolve from EditorCore's string catalog when the picker asks for
them. Snippet IDs, insertion templates, format scopes and user-authored names
remain unchanged, so existing overrides and saved snippets keep their meaning.

## Source and verification boundary

Original source unit: MostlyText `main` at `87552f7daf6aeaefc68dad55147f5f06a9b7034a`;
the reviewed branch was rebased onto `5630c2f3951a80a8792aa6282b192b3a01d556ce`.
The new catalog entries have source-English values. French, Japanese and Polish
entries are explicitly marked `needs_review`; they are translation work, not
accepted non-English copy. The picker still displays user-provided names
verbatim and reads resolved built-in names from the same `Snippet` field.

The focused package test creates a unique French resource bundle with six
distinctive marker names and calls the same built-in name resolver that uses
EditorCore's `Bundle.module` in production. It proves the names resolve through
the supplied bundle while IDs, insertion bodies and format scopes stay fixed;
it also checks that a user's replacement name stays verbatim and filtering
uses the resolved display name. The locked `SnippetLibraryTests` selection
passes all 12 tests. Xcode's catalog compiler emits en/fr/ja/pl resources;
readback finds all six keys in each language. These compiled values remain
English review drafts, not translation acceptance. The regenerated inventory
records 15 catalogs and 705 entries, including all six EditorCore call sites;
the structural/Transifex check and selected plain-string sink guard pass.
Strict SwiftLint, SwiftFormat and diff checks pass. No app or UI test host is
launched in the owner account. The isolated test desktop must verify actual
localized picker and accessibility presentation later.

This closes one identified hard-coded-string route under MostlyText #3. It
does not complete the whole UI-string audit, translation review, final language
freeze, pseudo-localization or native layout acceptance. The broader selected
sink ledger retains its other deferred source/metadata reviews.

# Built-in snippet name localization

## Owner summary

The six built-in Markdown snippet names appeared in the picker only as English
text, even when the rest of the app used a different language. Their display
names now resolve from EditorCore's string catalog when the picker asks for
them. Snippet IDs, insertion templates, format scopes and user-authored names
remain unchanged, so existing overrides and saved snippets keep their meaning.

## Source and verification boundary

Baseline: MostlyText `main` at `87552f7daf6aeaefc68dad55147f5f06a9b7034a`.
The new catalog entries have source-English values. French, Japanese and Polish
entries are explicitly marked `needs_review`; they are translation work, not
accepted non-English copy. The picker still displays user-provided names
verbatim and reads resolved built-in names from the same `Snippet` field.

The focused package test checks that each stable built-in ID has an owned
EditorCore catalog key in all four catalog languages. Existing tests cover
user replacement of a built-in ID and case/diacritic-insensitive filtering.
The locked Release `SnippetLibraryTests` selection passes 12 tests in one
suite. Xcode's catalog compiler emits en/fr/ja/pl resources with the six keys;
the 15-catalog structural/Transifex check passes with 705 entries. Strict
SwiftLint reports zero violations over 1,498 files, SwiftFormat needs no
changes, and the selected plain-string sink guard passes. No app or UI test
host is launched in the owner account. The isolated test desktop must verify
actual localized picker and accessibility presentation later.

This closes one identified hard-coded-string route under MostlyText #3. It
does not complete the whole UI-string audit, translation review, final language
freeze, pseudo-localization or native layout acceptance. The broader selected
sink ledger retains its other deferred source/metadata reviews.

# Folder search count copy — source correction

The E16 source review found five folder-search messages whose English catalog
values used plural nouns for a count of one. The affected paths are Replace All
confirmation and completion, unsearched and skipped-file notices, and the
result-row accessibility label. This changes count presentation only; the file
path in each result remains authored text and is never translated.

`FolderSearchCountCopy` now resolves each whole message using the SwiftUI
environment locale before presenting it. The catalog gives matches and files
independent plural substitutions where a sentence has two counts. The result
row composes a localized count phrase into a separate localized accessibility
sentence, avoiding an unsupported mixed String/plural substitution. The
French, Japanese and Polish values are draft translations marked
`needs_review`; they are not native-speaker acceptance.

The exact catalog compiles to all four locale resources with Xcode 26.6.
Direct compiled-catalog readback covered 0, 1, 2, 5, 12 and 22 for each
locale, including independent count forms and the preserved path, even when it
contains `%@`. The app test adds exact compiled-resource assertions. The
deterministic localization inventory was regenerated; all 60 localization
tool tests, structural and local Transifex-layout checks pass. A clean locked
Release build with `SWIFT_EMIT_LOC_STRINGS=YES` passed; compiler extraction
covers 784 first-party sources, 15 catalogs and 725 distinct keys with no
missing routes. The final locked Debug app/test `build-for-testing` passed
without launching the app. Full strict lint/format and ordinary compliance
pass, as do all 355 compliance tests. The final post-software string audit, native
visual/accessibility language review and string freeze remain open under #3.
The new app test is compiled; its hosted execution is required before merge.

The first local Debug test build stopped at a missing return in the new copy
helper before any test ran. The return was added without changing the catalog;
the first compiler failure remains in the local build log rather than being
treated as a passing test attempt.

An initial compiler-coverage command against a build without
`SWIFT_EMIT_LOC_STRINGS=YES` correctly found incomplete extraction. The clean
Release rebuild above used CI's flag; the setup error does not count as a
catalog failure.

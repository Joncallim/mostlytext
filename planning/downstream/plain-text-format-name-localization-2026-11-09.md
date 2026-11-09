# Plain Text format label through FileCore's catalog

## Owner summary

The read-only Supported Formats list, syntax-mode menu, status badge and
no-preview/outline messages all display `FileFormat.name`. Most built-in names
are names of languages or standards. `Plain Text` is a descriptive label, so
FileCore now resolves it through its own String Catalog before any of those
views receive it. Format IDs, extensions, content types, preview policy and
stored document bytes are unchanged.

## Source boundary

The registry and both last-resort `FileDocument` constructors use one
package-owned display-name function. Ordinary construction resolves against
FileCore's package bundle. A pure package test compiles the actual catalog
with the selected Xcode string-catalog tool, then injects its French `.lproj`
bundle into that same resolver. This distinguishes working compiled-resource
lookup from the English source fallback. Other built-in format names remain
their technical spellings; their stable IDs continue to drive format and
syntax behaviour.

The catalog contains the English source label and provisional French,
Japanese and Polish values marked `needs_review`. They are translation inputs,
not an approved language pass. Real Settings, status, Preview and accessibility
readback still belongs to the isolated test desktop and final candidate.

## Audit follow-through

The localization inventory is regenerated from this source. Its TextSearch
callsite-coordinate adjustments also reconcile pre-existing inventory drift;
this change does not edit TextSearch. The separate plain-string sink ledger's
`FileFormat.swift` deferred item should be updated after the parallel snippet
name and Finder metadata units are reconciled, so concurrent work does not
overwrite their decisions. Issue #3's complete string census, plural rules,
translation quality, pseudo-localization and native-language acceptance remain
open.

## Verification and an observed tooling limit

On Xcode 26.6 (17F113), `xcstringstool` compiles the FileCore catalog into
English, French, Japanese and Polish `Localizable.strings` resources; the
French compiled entry is `Plain Text` → `Texte brut`. The locked Release
package selection
`swift test --package-path MacDown2/Packages/MacDownKit --force-resolved-versions -c release --jobs 4 --filter plainTextDisplayNameUsesTheCompiledFileCoreCatalog`
passes one focused test. Changed-file strict SwiftLint and SwiftFormat, source
catalog/Transifex inventory and `git diff --check` pass.

The first version of that test failed: standalone `swift test` copied raw
`Localizable.xcstrings` into `MacDownKit_FileCore.bundle`, so a lookup there
returned the English source key. A subsequent probe compiled all locales into
one disposable bundle but still selected English under the owner's English
host language despite an explicit French `Locale`. The final test selects the
compiled French `.lproj` bundle itself and passes through the same resolver.
This proves the catalog and resolver path for that locale. A later pinned
arm64 Debug app and app-test `build-for-testing` also succeeded without
launching product code. The built app contains
`Contents/Resources/MacDownKit_FileCore.bundle`; its compiled French strings
map `Plain Text` to `Texte brut`, and Foundation resolves that value from the
embedded French `.lproj` bundle. The complete build log is retained outside
the repository at `/private/tmp/mostlytext-plain-text-app-build-20261109.log`.
On-screen language, Settings/status/Preview layout and accessibility still
need hosted and test-desktop readback.

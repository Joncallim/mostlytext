# Finder document and type label localization

## Owner summary

MostlyText declares document kinds and exported type descriptions that Finder
and Launch Services can show. Their nine distinct English labels now have an
`InfoPlist.strings` entry in each of the app's current catalog languages. The
document types, extensions, roles, type identifiers and public MostlyText name
remain byte-for-byte unchanged. This gives translators a package resource for
the OS-visible labels without changing which files the app can open.

## Source and packaging boundary

Baseline: MostlyText `main` at `8c50f687956dfae6ceb361f146d7f535efa85860`.
Seven `CFBundleTypeName` values and three `UTTypeDescription` values in
`MacDown2/project.yml` yield nine unique labels. Apple documents both fields
as localizable through the app bundle's `InfoPlist.strings` files:
[Launch Services document types](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html)
and [uniform type descriptions](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html).

The new en/fr/ja/pl files deliberately carry the exact source-English values.
The three non-English files are review drafts; no translated Finder copy or
locale acceptance is claimed. XcodeGen's generated project groups the four
files under one localized `InfoPlist.strings` resource in the app target.
The exact built app, Finder Kind/Open With presentation and clean-install
registration still need native verification after the icon/packaging work.

The first-party compliance inventory registers only this app resource path.
The Linux-safe localization check compares every declared document/type label
against all four resource files, rejects missing/duplicate/blank entries,
and requires the English values to match the source. A new declaration cannot
quietly add an untranslated Finder label. The existing String Catalog and
Transifex workflow remains separate; `InfoPlist.strings` is the OS metadata
route, not an in-app text lookup.

## Verification

`plutil -lint` accepts all four files, and `plutil` readback finds the exact
nine keys in each. XcodeGen generation places the variant group in the
`MacDown2` resource build phase. The new guard passes on this tree and rejects
both a missing French entry and a newly added unclassified document type in
temporary negative controls. The normal source-tree Compliance check passes.
No owner-account app or UI host was launched. This is one bounded E16 source
route; MostlyText #3's translation, pseudo-localization, native Finder and
final string-freeze criteria remain open.

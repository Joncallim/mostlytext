# Select the view language from multilingual catalogs

## Owner summary

Some views turn catalog text into a plain `String` before showing it. Passing
SwiftUI's locale to `String(localized:)` controls formatting, but a catalog with
both English and French can still return the English translation. This repair
selects the available catalog language first, then formats the selected text
with the view locale. It preserves catalog keys, authored text, file contents
and the default app language choice.

## Baseline and source finding

The baseline is `main` `d8d9bdc63d16fae2d4ded1ae1760c01aeb9e1477`.
PRs #341, #342 and #344 routed the view locale through plain-string paths,
but their French-only fixture did not establish language selection from the
real multilingual resource structure. A local Foundation reproduction with
`en.lproj` and `fr.lproj` returned `EN_PREPARING` from the full bundle for
`Locale(identifier: "fr")`; a bundle rooted at `fr.lproj` returned
`FR_PREPARING`. This is the failure that the new multilingual fixture retains.

`FileCore.ViewLocalizationBundle` uses Foundation's preferred-localization
selection on the source bundle and resolves the selected `.lproj`. The same
locale is still supplied to `String(localized:)` for number and interpolation
formatting. When no localized resource folder is available, the original
bundle remains the fallback. Package-owned messages retain their own package
bundle; app messages retain the app bundle.

## Verification and limits

The package regression checks language-region fallback (`fr-CA` to `fr`) and
English selection from one multilingual fixture. The existing app copy suite
now also uses both language folders, covering export, Preview, external-file,
open/save, progress, folder-operation and encoding-loss copy. The selected
plain-string ledger was reviewed for seven line shifts in unchanged AppKit
routes and now passes with 799 production Swift inputs, 60 selected sinks and
zero plain exceptions. All 15 catalogs retain 747 entries without structural
errors. Relevant hosted app checks, locked builds and lint qualify the final
head.
Installed non-English journeys, pseudo-localization layout, language quality
and final string freeze remain separate issue #3 criteria. The protected native
checkpoint remains deferred.

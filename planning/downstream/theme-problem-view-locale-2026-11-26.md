# Show custom-theme problems in the presenting language

## Owner summary

When a custom-theme import or storage operation fails, Settings should explain the problem in the language of the view currently showing it. Previously the model stored already-rendered text, so a later language change could leave that problem in the old language. The model now retains the failure category and the Settings view resolves the existing catalog entry when it draws the message. Theme files, selection, warnings, retries and storage authority are unchanged.

## Baseline and boundary

This slice starts from merged main `5792ead35a3db053a544f06a4757a0b4134ef417`. It follows #3's current source audit and E23's existing theme catalog. The model remains main-actor owned and records one `ThemeCatalogProblem` value for startup, refresh, import, duplicate, delete and completed-with-warning outcomes. `ThemeManagementSection` owns its `Locale` and resolves the copy at the final `Text(verbatim:)` sink. External file errors and the preserved competing filename are classified without retaining an arbitrary error object; the file operation is not repeated when the language changes.

The eleven extracted app catalog keys in the changed sources are identical before and after the refactor. Existing French, Japanese and Polish theme strings remain draft translations requiring native review. A focused oversized-import regression checks unchanged source bytes and catalog state while resolving the same retained failure in English and French. It does not close #3's whole-app string audit, installed non-English, pseudo-localization or final freeze criteria. The protected native checkpoint remains deferred by the owner.

Before the change, a source-equivalent expression against the built app's
English and French resource bundles returned `Theme files are limited to 64
KiB.` for the stored copy while the selected French bundle returned `Les
fichiers de thème sont limités à 64 Kio.` The equality control failed with
exit 1. This establishes the locale-selection mismatch at the copy boundary,
not an installed-app visual result. The pinned local Debug app and test bundles
compile without launch; the compiled French resources contain the same theme
copy. The 23 localization-inventory and 21 compiled-coverage tool tests pass,
the refreshed 15-catalog/747-entry inventory has no structural errors, the
selected plain-string audit still has zero plain exceptions, and ordinary
compliance passes. The focused app regression and required CI run on a hosted
macOS test environment before merge.

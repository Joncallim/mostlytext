# View language in status, outline and theme copy

## Owner summary

Several editor labels had catalog entries but converted them to plain strings
before SwiftUI could apply the presenting view's language. A French view inside
an English process could therefore show English status and outline copy. This
change selects the app's matching localization resource for those labels while
leaving document text, filenames, theme data, file conversion and menu actions
unchanged. It extends the multilingual-bundle correction merged in PR #345.

## Baseline and affected routes

Base main is `415018ef2843cda435f1f2fc14cd7709172afc1c`. The affected
plain-string routes are editor line/column, counts and indentation; the empty
Markdown/JSON outline placeholder; sidebar section/folder fallback and reorder
accessibility copy; high-contrast theme names in settings and the menu; and
line-ending and automatic syntax labels. They already use app catalog keys.
The French test bundle has both French and English entries so selecting the
process language by mistake produces a different value. Authored outline
titles and user/theme names remain verbatim.

The shared `FileCore.ViewLocalizationBundle` remains the resource selector.
The app passes the SwiftUI locale at the point where each plain string is
created. Global menu commands receive their environment locale through
`WorkspaceCommands`. No new translation, catalog key, dependency, persistence
format, external authority or renderer path is introduced.

## Verification and limits

The owning app tests cover the multilingual status, outline, sidebar,
line-ending and syntax copy, and the compiled app catalog's French high-contrast
theme names. The selected plain-string sink ledger records the unchanged
tracked routes and the shifted sidebar line. The final PR records its exact
source identity, focused test results, final-head hosted checks and any first
failure. Protected installed-app language, accessibility and pseudo-localized
layout observations remain deferred. This is a bounded source repair under
MostlyText #3, not the full string audit or final language freeze.

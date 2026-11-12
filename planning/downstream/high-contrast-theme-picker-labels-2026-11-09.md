# Localize the descriptive high-contrast theme choices

## Owner summary

The two built-in high-contrast choices describe an accessibility setting, so
their labels belong in the app's String Catalog. The other bundled theme names
are product or theme titles, and custom names belong to the user. The picker
and Theme menu resolve only the stable `high-contrast-light` and
`high-contrast-dark` IDs through the app catalog; theme JSON, resource filenames,
selection IDs, copied theme names and exported bytes keep their existing values.

## Scope and evidence

`ThemePickerDisplayName` supplies a display string for Appearance settings,
Theme management and the Theme menu. It leaves every other theme's name
verbatim. The English catalog entries and French, Japanese and Polish draft
values are present, with non-English states marked `needs_review` pending native
language review. The app-hosted test reads an actual compiled French `.lproj`
bundle, checks both high-contrast labels, and verifies ordinary bundled and
custom names stay verbatim in the picker route. A duplicate's `ThemeFile`
still carries the original English name.

This source correction does not establish translation quality, layout or
accessibility readback in the installed app. Those remain under MostlyText #3.

## Local verification

- Swift syntax parsing, strict SwiftLint, SwiftFormat lint and `git diff --check`
  pass for the changed sources.
- `xcstringstool compile` produces the expected English, French, Japanese and
  Polish strings. The Debug app bundle contains the French translations, and a
  disposable bundle readback resolves the compiled French and Japanese values.
- An arm64 Debug `build-for-testing` of the app and app test bundle succeeds
  without signing or launching the app. The hosted test has not run in this
  account; CI and the separate test desktop still need to execute it and review
  the installed app's labels, layout and accessibility output.

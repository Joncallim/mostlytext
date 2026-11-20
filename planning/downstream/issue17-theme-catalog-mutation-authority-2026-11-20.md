# Theme catalog completion authority — 20 November 2026

## Owner summary

An import or duplicate can finish after the theme catalog has refreshed or after
the user has chosen another theme from the still-available menu. The app now
selects the result only when the current catalog still contains those exact
theme values and no later explicit theme choice has occurred. An older storage
failure warning also cannot mark a newer, healthy catalog unavailable.

This is a bounded editor theme repair under issue #17. It does not complete
the issue's whole-code disposition, protected native journeys, or final audit.

## Source path and decision

`ThemeCatalogStore` owns writes and monotonically increasing catalog revisions.
`ThemeCatalogModel.publish` already refused an older revision. Its mutation
completion nevertheless used the old mutation's theme and warnings after that
refusal. `ThemeController.select` resolves a theme by identifier against the
current available set, so a removed theme would not be selected, but a
superseded completion could still report a removed affected identifier or
override a later menu choice. A changed theme with the same identifier could
also be selected from the newer catalog by the old completion.

The repair keeps the store and controller ownership model. The model captures
the controller's explicit-choice generation when each import/duplicate starts.
On completion it compares the returned theme with the currently published
theme file and checks that generation before selecting. An unrelated catalog
refresh that retains the result still permits selection. The mutation's
directory/refresh failure status applies only if its revision still owns the
published catalog. Per-operation warning text remains visible.

## Controlled cases and limits

The app model tests cover a removed theme, a later A→B→A user choice, a newer
same-identifier theme with changed values, an unrelated newer catalog revision
that retains the import, and an older warning after a newer healthy revision.
They use an actual `ThemeCatalogStore` and managed files; only the final
completion delivery is controlled at the model boundary. The tests do not
claim installed UI or owner-desktop acceptance.

The first hosted before-fix run, [44757531511](https://github.com/Joncallim/mostlytext/actions/runs/44757531511),
exposed a fixture error: an import assigns a new managed identity, while the
new deletion case initially used the incoming file's identity. That case
threw `invalidImportChoice`. The later-menu-choice case separately failed its
intended assertions on the unmodified selection code. The fixture correction
uses the identity returned by the store; the original failure is retained.

The corrected before-fix [run 44760379470](https://github.com/Joncallim/mostlytext/actions/runs/44760379470)
failed the four intended removed-theme, stale-warning, later-choice and
changed-theme cases; the unrelated-refresh control passed. The initial
final-head broad Debug editor/theme [run 44760745871](https://github.com/Joncallim/mostlytext/actions/runs/44760745871)
timed out after ten minutes in unrelated highlighting tests, without an
assertion failure. Its matching Release selection passed. This PR limits that
workflow to the 149 actual `ThemesTests` cases when the PR diff contains only
theme source/app-model changes and supporting evidence or workflow files.
Editor or highlighting source changes still run the original complete probe
and bitmap, orientation and performance controls. The complete CI app-test
job remains the authority for the new `ThemeCatalogModelTests` cases.

The repository-wide issue audit and exact-head hosted verification results are
recorded on the PR and issue comment after integration. Strict release
compliance remains governed by issue #14 and is not changed by this patch.

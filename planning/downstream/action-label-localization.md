# Localise owned action and structural labels

## Owner summary

Existing app-command titles, sidebar section headings, Find option help and
editor undo-action names are stored as plain English Strings. JSON outline
root labels also use English structural nouns. These values reach user-facing
surfaces without the localization pipeline, so a compiler-key coverage check
cannot find them until their owners perform the catalog lookup. Add literal
lookups at those owners, keeping every command ID/action, authored name, edit,
undo grouping and JSON value unchanged. This supports MostlyText #3 and #6;
actual native menus, Find controls and language/layout review remain separate.

## Source and ownership

Start from main `f3860c3d594a72921d0fea1b4732dcc1500d2810` plus the exact PR53
and PR54 source candidates through `91154ddc9f8c26911e88f8539734669715417fc2`.
Those PRs must merge first, and the anticipated main merge tree must match the
qualified candidate before integration. PR54 owns compiler/catalog coverage;
this unit adds the already identified plain-String routes to that pipeline.

## Contract

Wrap only static first-party titles in `AppPaletteCommand.standard`, the three
`SidebarSection.title` branches, the four Find option help strings and its
English W/Sel button labels with app-owned String(localized:) calls. Keep the
case/regex symbols Aa and .* literal. Keep all public/private interfaces,
availability predicates, commands, sorting and authored text-filter names.

EditorCore's literal undoActionName arguments, its case/indent/move/heading
branch names and snippet undo label use its existing bundle: .module. The app's
two JSON-format undo labels use the main bundle. Localize only label values;
do not change transaction generation, selection, undo registration or text.
JSONSupport's Object/Array root titles use its own bundle. JSON field names,
strings, numeric spellings, true/false/null syntax and structural IDs remain
verbatim. Existing deliberately stable filesystem names, format codes, symbols,
renderer output and test-guard operational messages are outside this UI-label
correction; do not translate persistent identities or authored content.

Register absent exact compiler keys in existing catalogs, preserving every
existing entry/translation. New French/Japanese/Polish values are English
needs_review drafts. Do not add a label abstraction or change model types just
to make tests easier. Any required action/edit/identity behavior change stops
this unit for an explicit architecture reconciliation.

## Verification and completion

Capture an exact call-site manifest before editing and prove that replacing
the localized expression by its original literal reconstructs the old source.
This makes the label-only scope independently inspectable. Qualify those exact
Foundation localization expressions with actual compiled catalogs in a
non-application fixture, with only bundle substitution for app-owned lookups.
Distinctive separate marker resources must pass current expressions and fail
the original literals, with exact restoration. Do not execute AppKit, EditorCore,
the app/helper or app-target tests locally to test labels.

Run the complete owned-source compiler extraction and exact catalog guard,
catalog/configuration controls, strict lint, pinned format, full combined hosted
package/non-UI app checks, locked compile-only universal Release and resource/
metadata/helper/artifact readback. Existing real transaction/command/JSON tests
run hosted; no local label fixture is claimed as native editing acceptance.
Record exact source, substitutions, failing controls and integration evidence;
retain final freeze, translations, plural/layout/VoiceOver and native gates.

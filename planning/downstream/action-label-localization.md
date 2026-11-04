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

## Find view layout reconciliation before applying it

The new catalog expressions make SwiftFormat wrap several Find option calls,
and strict lint now reports a 256-line type body against its unchanged 250-line
limit. Move the existing private optionToggle helper to a private method in an
extension in the same file. It uses only its existing parameters; keep the
signature, body and privacy unchanged. Do not suppress or raise the lint limit,
compress unrelated code, or move state/observation. The source-scope proof must
put this unchanged helper back in its original declaration position before
comparing reversed parser trees, and record that explicit layout normalization.

## Source qualification checkpoint

There are 62 literal routes across 19 files and 54 owned keys; 38 keys were
absent and are now registered, bringing the same 15 catalogs to 671 entries.
Before formatting, reversing the new expressions reproduces the exact original
source bytes. After formatting and restoring the unchanged Find helper's
declaration position, Swift's parse-only compiler produces identical parser
trees after source-location/context-pointer normalization. Parsing does not
resolve or execute the AppKit/editor imports. No command or editing logic is
silently excluded from this scope comparison.

Six Foundation tests in three suites pass Debug/Release against the exact
localization expressions and actual compiled catalogs. Only app-owned default
main-bundle lookup is substituted with the fixture bundle. Distinctive separate
markers pass all 62 routes; the original literals fail 62 assertions; exact
restoration passes. Two pre-existing app keys, New File and Save As…, intentionally
use source-language English fallback rather than explicit English resources.
The fixture initially expected explicit resources for both, then was corrected
to test that actual fallback while retaining the failed observation. Production
catalog entries/translations were not rewritten to accommodate the fixture.

Strict lint and pinned formatting pass after the documented helper move; source
Compliance and 19 catalog/configuration controls pass. Final complete compiler
coverage, locked Release/resource readback and full hosted combined behavior
tests remain required before merge. Final language/native acceptance stays open.

## Reproduced installation-title correction before implementation

The remaining action-message review disproved the assumption that every needed
change is a label-only lookup. TextFilterCommands uses String(localized:) for
`^[Added count Example Script](inflect: true)`. The Foundation-only source probe
returns the literal markup for counts 0/1/2; AttributedString(localized:) returns
readable Added 0 Example Scripts / Added 1 Example Script / Added 2 Example
Scripts. This is a real formatting defect, separate from the 62 lookup routes.

Add a small static installedExamplesTitle(count:bundle:locale:) value formatter
to the existing TextFilterCommands type. Resolve the existing catalog key with
AttributedString(localized:) and return its plain characters. The existing
success alert calls that formatter; installation, failure/no-op branches and
modal/window policy remain untouched. No new key or catalog translation is
required. The formatter owns count agreement and accepts explicit resources for
qualification without constructing a command or NSAlert.

Test that actual helper and compiled English count forms, all four locales'
absence of raw markup, and a separate explicit-bundle sentinel. Locally extract
only this unchanged Foundation function into a namespace fixture. The actual
old String expression must fail the new readable-output assertions. Record this
functional correction separately; the 19-file parser-reversal proof applies
only to the earlier 62 label routes, not to this intentionally different
formatter. Full hosted qualification must use the new combined head; the
superseded partial CI is not a release or correctness pass.

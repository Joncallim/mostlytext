# Localise remaining preview and contribution labels

## Owner summary

The preview diagnostic badge constructs an English accessibility label from
"error"/"warning" fragments. The command palette also appends an English
"user command" suffix to an authored title. Route those owned labels through
the app catalog, with full count/plural messages and unchanged authored names.
The empty table-of-contents contribution and folder sidebar fallback likewise
need catalog-owned placeholders. Reconcile compiler-extracted owned strings
with their existing catalogs so pipeline use does not hide missing resources.
This supports #3, #6, #7 and #10; it does not establish final localization,
VoiceOver, navigation or native feature acceptance.

## Source and reconciliation

Main is `8158068771a2012c27885d7ac4808cf73af7ffb1`; this unit starts from PR53
candidate `b0fe54dff74d1df833f496e3fdcb659a5bfd9e68`, including PR52. Both must
merge first. Confirm the anticipated main merge tree equals the tested tree.
An actual compile-only SwiftUI probe confirms that conditional literal labels
such as Expand/Collapse are extracted normally, while the mixed authored-title
command label is not. Do not replace correctly inferred LocalizedStringKey
branches merely because their syntax is conditional. The probe's first attempt
used an invalid fixture modifier; its corrected compile-only result is retained.

## Contract

Add an internal Foundation `PreviewDiagnosticLabel` count value with error and
warning cases. Its message accepts an explicit bundle/locale for resource
qualification and defaults to the app main bundle/current locale. Two literal
signed-count keys use full catalog plural forms, retaining English singular
and plural wording. The existing badge switches severity to this formatter;
severity selection, count, popover and lifecycle remain unchanged.

The existing command-palette conditional uses String(localized:) only for the
owned suffix branch; the other branch remains the verbatim authored title.
The folder label localises only its fallback, never the actual folder name.
The TOC contribution localises only "No headings found." through its existing
package bundle, escapes that plain text with its existing CommonMark escaper,
and retains the existing emphasis/parentheses. Heading titles and generated
link/anchor behavior remain unchanged; no held TOC navigation is activated.

Use compile-only Xcode extraction on the current locked Release source. Map
only first-party app and package keys to their existing owned catalogs; never
copy dependency/test strings or overwrite existing translations. Add absent
keys as English source values and explicitly needs_review English drafts for
French/Japanese/Polish. Keep formatting placeholders exact. If extraction
requires a different target, package pin, runtime launch or public behavior,
stop and reconcile this contract rather than broadening it silently.

## Verification and limits

Test the actual Foundation count formatter against Apple-compiled resources
for four locales, count boundaries, fallback and distinctive synthetic markers;
the actual old English-fragment construction must fail those marker assertions.
Compile-check final view call sites without executing SwiftUI/AppKit/WebKit.
Qualify actual TOC value/helper bodies in a non-app fixture, preserving source
identity and recording any namespace/bundle substitutions. Show an old-source
failure and keep authored-heading/markup behavior unchanged. Verify literal
compiler keys, canonical catalog/configuration structure, pinned lint/format,
full combined hosted checks, locked universal compile-only Release and actual
resource/artifact readback. Record missing-key disposition and exact source.

No native or final linguistic sign-off, final string freeze, new renderer,
network/file authority, dependency, budget, editing policy or Quick Look target
is introduced. Native tooltip/VoiceOver/layout and final translated plurals
remain open; English review drafts do not meet language-quality criteria.

## Compiler coverage refinement before adding its guard

The locked compile-only Release extraction found 726 owned source/line/key
routes and 615 distinct catalog/key pairs across all 15 catalogs. There are
327 missing route references, representing 282 distinct keys, before reconciliation. Most
are existing correctly extracted app labels; the package omissions also include
escaped-quote and signed 32-bit/64-bit format-key mismatches. Retain existing
entries/translations unchanged and add the exact compiler keys as review drafts;
do not reinterpret a mismatched older key as accepted translation evidence.

Add a read-only standard-library coverage tool that compares actual Xcode
stringsdata with the current owned source/catalog paths. Normalize paths in its
receipt; ignore dependency extraction, reject unknown owned tables/catalogs,
and fail on empty, malformed, missing-source or missing-key evidence. Require
all owned application/helper/package Swift compilation inputs (excluding resource
scripts) to have extraction records, including files with no keys. This catches
an accidentally partial extraction rather than treating zero results as a pass.
Record exact source hashes and reject inconsistent architecture duplicates.

Enable string extraction in the existing hosted Release app/helper builds and
run the guard on that build's intermediates. Derive the intermediates path from
actual Xcode build settings, not a guessed home directory. The code/pin/signing
and UI-execution policies remain unchanged. Add deterministic positive and
negative Python controls for ownership, completeness, format-key identity and
duplicate/malformed records; run them in Compliance. This is compiler/resource
coverage of currently built code, not an exhaustive discovery of every plain
String or final native/string-freeze acceptance.

Select the actual Xcode configuration as well as its intermediates root.
Debug and Release may deliberately compile different conditional strings;
another configuration's old records must neither satisfy completeness nor be
mistaken for an inconsistent architecture of the checked Release build.

## Qualification checkpoint

The complete owned compilation set has 682 Swift inputs. All have extraction
records; architecture duplicates agree. The guard reproduces 327 missing
source/line routes before reconciliation and zero afterward, for the same 615
distinct compiler keys. Add 282 exact keys plus the five corrected label keys,
bringing the inventory to 633 entries across the existing 15 catalogs. Existing
catalog entry data/translations remain unchanged; obsolete mismatched keys are
retained as history rather than silently relabelled as accepted translations.

Six Foundation tests in two suites pass Debug/Release for the exact count
formatter and TOC value/list/escape methods, with actual compiled locale
resources. A supplied minimal heading model exposes only the two fields used
by those methods; this is not contribution parsing or native navigation.
The original English-fragment label body fails four marker assertions, while
the new formatter and exact restoration pass. A separate TOC marker containing
Markdown/HTML punctuation remains escaped plain text; the old list body fails
that actual assertion and exact restoration passes. An initial fixture literal
had an invalid backslash escape; its failed compile is retained, and only that
fixture was corrected before the successful Debug/Release qualification.

Eighteen Python coverage controls and 19 catalog/configuration controls pass,
as do source Compliance, strict lint and pinned formatting. Locked universal
Release compilation with extraction passes for the corrected Swift sources;
all 287 added keys were read back in four compiled locales (1,148 lookups).
PR54 merged at `18f3599b` with the same tree as qualified `91154ddc`. Full
CI 41773915889 passes 3,425 package and 616 app tests, locked builds, actual
compiler coverage and metadata/helper/pin checks. Compliance and GitGuardian
pass. Non-English drafts, final
plural/language/layout/VoiceOver review and the native hold remain unchanged.

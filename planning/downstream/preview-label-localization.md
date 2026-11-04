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

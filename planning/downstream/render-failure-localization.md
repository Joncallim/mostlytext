# Localise the diagram failure details

## Owner summary

Mermaid, D2 and Graphviz preview blocks show a translated failure summary but
leave four details in English: no image, timeout, output size and unavailable
renderer. Route those details through the existing app catalog while preserving
source/syntax messages verbatim. Rendering, cancellation, state and native
presentation stay unchanged. This is a bounded #3/#7 source fix, not final
language/native acceptance or activation of held preview/Quick Look behavior.

## Baseline and ownership

Main23a42955a54495590eadad9b823e96f1f2eb4a28; PR51 export recovery is independent
and will be incorporated before combined qualification. The three existing
DiagramBlockView types own their render-state transitions; their known-error
switches currently return identical literal details. The app owns these strings,
so its main bundle is correct. Existing renderer syntax strings and unknown
error.localizedDescription are external diagnostic text and remain untouched.

Add one internal Foundation-only DiagramFailurePresentation value with four
cases and message(bundle:locale:) using String(localized:). Follow the existing
ExportDiagnosticPresentation injection style. Views call it for the existing four
branches only; don't move or duplicate render logic, NSImage work or tasks.
Size remains an Int, uses its actual extracted signed format key and catalog
plural rules; preserve normal existing English, correcting singular one-byte
wording. Add explicit source entries and English-review drafts for fr/ja/pl,
all needs_review. This does not claim translated linguistic quality.

## Failure, authority and limits

No document content is translated or reinterpreted, no renderer is added, no
file/network/profile authority changes and no persistent setting/migration.
Only failure-message construction changes. Cancellation continues to suppress
stale results exactly where it does now. A missing catalog keeps the existing
English fallback. No final string freeze while remaining UI is unsettled.

## Verification

Test the actual compiled app catalog for four locales and boundary counts in
hosted non-UI app component tests. Locally use only the unchanged Foundation
formatter and compiled catalog in an owned non-app fixture; replace the test
bundle import/accessor, never execute app/views/AppKit/WebKit. For an effective
bundle-routing control, use a separate synthetic catalog copy with distinctive
non-English markers, keep production catalogs unchanged, and show that forcing
the wrong bundle fails. Static call-site guards must reject the original view
literals and accept each shared formatter route. Preserve original engine syntax
and unknown diagnostics; no new generic wrapper around arbitrary error messages.
Run catalog/configuration controls, strict lint/pinned formatting, full combined
hosted CI, locked compile-only universal Release and read-only artifact checks.
Refresh the canonical string inventory after integration. Record source hashes,
failed-before controls and real results. Keep native hover/help, layout,
VoiceOver, pseudo-localisation and translation review open.

## PDF error/recovery copy reconciliation before implementation

The broader app error-description audit found six PDFSnapshotFallback.FallbackError
descriptions plus its recovery suggestion, and six PDFExportAdapter.PDFExportError
descriptions plus two recovery suggestions, returning English String literals.
These are normal user-facing LocalizedError details, not test-only guard text.
Include these fifteen keys in this same app-owned rendering-failure unit.
Wrap the existing literals with String(localized:) in their existing enums;
retain enum identities, cases, control flow, printing and cancellation exactly.
Do not add a formatter abstraction merely for testing these single call sites.

App component tests exercise only the nested error values and compiled catalog,
without creating a print adapter or WebKit object. The local non-app fixture
extracts the two unchanged value-enum bodies, removes only their parent namespace
in test references and substitutes the fixture resource bundle for the app's
implicit main bundle. This is not PDF execution or a native language override.
Use separate synthetic catalog markers and the actual old enum bodies to prove
that catalog lookup is effective; retain production catalogs unchanged. Extend
the static source guard and compiler-extracted key check to all fifteen routes.

The three legacy-import labels already return LocalizedStringKey and are not
hard-coded String failures. UITestLaunchGuard's English operational refusal
messages are deliberate test-only diagnostics; do not translate guard policy
or treat those strings as shipped application copy. No new native gate is waived.

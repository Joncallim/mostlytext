# Localise equation failures and export diagnostic summaries

Users should receive equation failures and export issue counts through the same
String Catalog pipeline as other export errors. Today MathContribution's generic
failure interpolates English directly, and ExportCoordinator builds its issue
count and hidden-message summary in English. This correction preserves authored
source, per-equation fault isolation, cancellation, generation identity and the
six-message display limit. It does not change parsing, rendering or publication.

Baseline main: 242054cf3bfdf8937a695542adc1d3029777c5ab. Related issues: #3
(localisation pipeline) and #9 (math diagnostics). Final language/layout/native
acceptance and the broader Preview math adapter remain open.

Math owns its existing generic message: route it through String(localized:,
bundle: .module), with the original LaTeX as an opaque substitution. Preserve the
separate invalid-dimensions diagnostic; never leak arbitrary renderer exception
text. Register both existing Math messages in fr/ja/pl, explicitly needs_review.

The app owns a small Foundation-only ExportDiagnosticPresentation value. It takes
message strings, produces the title/body, and bounds visible messages at six.
It uses String(localized:) with the app bundle for count-aware title and omitted
count, retaining message order and exact diagnostic text. Allow bundle/locale
injection internally so tests can exercise actual compiled catalog resources.
ExportCoordinator uses this value to populate its existing alert; alert lifetime,
origin ownership and cancellation remain unchanged.

Commit this architecture before implementation. Add real contribution regressions
for Unicode/percent/source text, sibling isolation, corrected subsequent source,
and unknown renderer failure. Add app tests for six-message boundary/order and
compiled catalog plural selection at English/French/Japanese/Polish edge counts.
Translations are review drafts, not a final E16 freeze or human-language verdict.

Run the source-identical non-application Foundation fixture, catalog structural
validation and negative controls, pinned format/strict lint, locked compile-only
Release and full hosted package/app CI. Never launch the product/AppKit/WebKit on
the owner account. Native alert/layout and Preview accessibility remain explicit
downstream gates; no whole issue closure follows from this narrow correction.

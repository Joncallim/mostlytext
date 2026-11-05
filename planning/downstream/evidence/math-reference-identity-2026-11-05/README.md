# Preserve reference identity through derived label replacement

The real parser loses the target of `[$x$][]` when a derived marker replaces its
label without preserving the implicit key. The new source-bound MarkdownEngine
helper converts affected collapsed/shortcut references to their original explicit
key. It uses exact source SHA-256 and original UTF-16 scalar/CRLF boundaries,
rejects overlapping/duplicate replacement authority, and removes only parser-proved
container prefixes from multiline keys. Full references, inline destinations and
unrelated links stay unchanged; no URL, title or definition is synthesized.

An expanded ASCII corpus found another real failure: restoring the raw key of
``[$x$`tail][]`` supplies a closing backtick across the label boundary, turning literal
text into code and losing the link. The failed source/tests, three-issue full log
and focused diagnostic are retained. The correction protects only original
unescaped literal backticks outside real code/HTML and replacement spans, respecting
odd/even backslashes. The original raw key is unchanged. Seven explicit regressions
preserve actual decoded heading text, targets and titles; comparisons use exact
UTF-8, including canonical-lookalike keys with byte-distinct destinations/titles.
No document source is written or normalized.

The final inspected Foundation fixture passes **414 tests / 43 suites** in Debug
(12.071 s) and Release (3.495 s), including existing source/analysis, the unchanged
100,000 partial-input engine corpus and worker controls. The new real-parser corpus
covers LF/CRLF/CR, nested quote/list/lazy keys, escaped brackets, Prepend/combining/
variation selectors/ZWNJ/emoji, table cells/escaped pipes, multiline definitions/titles and multiple equations
per link. All 119 exact source/test/resource files and the local MathSyntax dependency
have SHA-256 receipts. The only namespace substitution is the previously documented
unused outer SwiftUI Math View. No SwiftUI/AppKit/WebKit/font/drawing/product/CLI/
signing code executes locally. Use reproduce.py with an existing engine Git repo
and new output path; preparation checks hashes and does not execute source code.

Export's production composer now supplies its source-bound facts to the existing
DerivedContentComposer. Repairs follow actual per-fragment admission, join accepted
sentinels before the existing cmark pass and participate in its coordinate map.
Exact source/body suffix comparison avoids materializing another whole body.
Invalid binding, colliding edits or expanded-input budget failure keep the authored
body and report a catalog-backed error instead of publishing an unproven derived
snapshot. Stale/failed individual fragments cannot request repairs. Existing HTML
sanitization, authored URL policy, resource authority and export pipeline stay in use.
The existing ValidationContext was moved unchanged to a separate file to retain the
400-line source limit; the first length-lint failure is retained.

Actual MarkdownEngineTests and ExportServiceTests targets compile locally. New
Export tests cover the real cmark bridge and full HTML/PDF preparation, coordinates
through front matter, original targets/titles, unsafe URL policy, literal backticks,
stale/failed fragments, bad source facts, suffix collisions and expanded-input caps.
The first hosted run (42061416370) executed all 3,553 package tests and found three
failures in the parameterized Unicode test: its `String.contains` assertion missed
a present ZWNJ because the search uses grapheme boundaries. The raw HTML proves the
scalar remains after the closing link tag. The retained Foundation-only diagnostic
reproduces the false negative, proves scalar/literal UTF-16 presence, and rejects an
absent control. The assertion now checks `unicodeScalars`, preserving the exact
scalar requirement. No production change or relaxed timeout was needed. The full
first failure log and exact before-test source are retained. The corrected Export
module tests compile locally; a fresh hosted full run must qualify the changed head.
Full strict lint and pinned format pass; inventory passes. The new fr/ja/pl catalog
translations remain needs_review for the final native language gate.

The final fixture's first rerun stopped at setup because its frozen local package
folder changed the SwiftPM identity from MathSyntax to frozen-MathSyntax. Moving the
same hash-verified bytes under a MathSyntax leaf restored identity; the failed setup
log is retained. Final passing logs are separate. The local dependency was frozen
before deleting the verified merged parent branch; no test assertion was weakened.

This is a shared source-transport/export correctness unit. Preview's scalar-safe
native adapter and joint production math grammar/diagnostics/navigation remain to
activate. Whole cmark/Preview parity, final resource calibration, real PDF/VoiceOver/
Release and exact-artifact acceptance remain open.

# Front-matter line-ending fidelity — 5 November 2026

The front-matter line helper previously recognized only LF, while SourceMap and
the Markdown parser support LF, CRLF and CR. CR-only or mixed headers could
therefore leak YAML into the rendered body and omit its original line offset.
The fix consumes CRLF as one ending and records exact original UTF-16 offsets
for all three. A final empty line now agrees with SourceMap. The body remains
an exact slice of authored source; existing normalized-LF YAML parsing remains
unchanged, including the original CRLF regression assertion.

[Verification](verification.json) records every source/test hash, exact locked
Swift Markdown/cmark/Yams Git/archive identity, command and raw/gzip log hash.
Unchanged source files are copied into the same kind of owned, library-only
Foundation parser/scanner fixture as the
[diagram extraction proof](../parsed-diagram-source-2026-11-05/README.md).
Its manifest and reproduction procedure apply; add the two listed front-matter
test files and verify the per-file hashes before executing. No app, SwiftUI,
AppKit or WebKit target is built or run by this fixture.

At unchanged baseline `48d5be77f6015d37af369719549682b32eee406e`, the 101-test,
10-suite fixture records 28 real failures. Fixed source passes all101 in Debug
and Release. The same current diagram golden tests and existing parser/scanner/
front-matter suites remain in the fixture. Cases cover all three/mixed endings,
BOM/emoji, `---`/`...`, exact body/metadata values/original coordinates, EOF,
empty metadata, thematic-break and unterminated-header rejection. All316
Compliance controls/source inventory, pinned format and strict whole-tree lint
pass. Full locked hosted app/package/CLI/build qualification remains a separate
PR gate; these component results are not native or whole-app acceptance.

No source file is rewritten, public model/pin changed, parser policy relaxed,
or native receipt retargeted. Real-app format/export, Release memory/budgets,
Preview/Export parity and exact-candidate/native obligations remain open under
#6/#11/#17. PR72 must qualify and integrate first. The existing renderer timeout
failures and six strict compliance predicates remain unresolved.

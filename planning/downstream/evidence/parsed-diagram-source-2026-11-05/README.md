# Parser-owned exported diagram source — 5 November 2026

Quoted/list-nested diagrams must receive decoded diagram text rather than raw
Markdown container syntax. The existing parser already owns that distinction.
The fix carries its code literal into the immutable block and lets the three
export scanners consume it, retaining their original source ranges. One parser
terminal LF is removed; genuine indentation, operators and blank lines remain.
Manual models without the optional metadata retain the existing fallback.

## Actual reproduction and qualification

[The record](verification.json) binds every copied source/test file, dependency
Git/archive identity, command and raw/compressed log hash. The source is copied
byte-for-byte into an owned library-only SwiftPM fixture; no product app,
SwiftUI, AppKit or WebKit target is imported/executed. The
[fixture manifest](fixture-Package.swift) uses exported local copies of the exact
locked Swift Markdown/cmark/Yams commits; no dependency source edits.

At baseline `a95ff1fc4498e925eb1582fa6eb9e7fab5baf5ad`, the identical ten new
regression functions record **40 real expectation failures**, all in renderer
input, with zero source-range failures. The fixed source passes **69 tests in
8 suites in Debug and Release**, including seven relevant unchanged parser/
scanner test files plus their unchanged fixture helper. All four language tags,
quotes/lists/combined containers, unterminated fences, content backticks,
blank/empty bodies, Unicode/front matter and LF/CRLF/CR are covered. All316
Compliance controls, source inventory, pinned SwiftFormat0.63.1 and whole-tree
strict lint pass. These component passes do not establish a full product pass.

To reproduce, export the named dependency commits into `Dependencies/swift-markdown`,
`Dependencies/cmark` and `Dependencies/yams` beside the fixture manifest. Copy the
listed source files unchanged into `Sources/<module>` and listed tests unchanged
into `Tests/ScannerTests`. For the old-source negative, use the named baseline's
production files with this revision's ten-function regression file. Run the
commands in the record with `SWIFTCI_USE_LOCAL_DEPS=1`. Every input's hash must
match before running. The baseline is expected to fail; preserve its actual log.

The first corpus also assumed CR-only front matter was supported; it is not.
The corrected corpus keeps front matter LF and varies the fence line endings,
so it isolates this diagram contract without weakening its source/range checks.
Both initial logs are retained. The first related-suite setup omitted its
existing Fixtures.swift helper; debug/release compilation logs are retained,
and qualification uses that unmodified helper. Neither setup failure is called
a successful test or a production regression.

## Remaining acceptance

This fixes export input extraction, not nested Preview presentation or every
F06/parity/native requirement. Preview, renderer engine, timeouts, pins and
native receipts are unchanged. The two previous full-suite renderer timeouts
remain tracked and unexplained. Code literals add retained immutable snapshot
text; whole-app memory/performance calibration remains open. Final full hosted
CI and actual merged-source qualification are recorded in the PR/owning issue;
no package fixture substitutes for those or native/exact-artifact acceptance.

# Shared source grammar/value foundation

The unchanged actual production MathSpanScanner fails four contract assertions:
currency consumes phantom prose, an even backslash run escapes an opener, a
closer before a digit is accepted, and whitespace can open inline math. Its two
Foundation-only source files are byte-verified against main30d7692f and retained
with exact baseline tests/output. This is the original scanner, not a mock.

The new independent Foundation-only MathSyntax package passes19 Swift Testing
functions/two suites Debug/Release. Declared expectations cover exact original
UTF-16 full/body ranges and expression units; inline/display/Unicode decimal and
whitespace policy; complete0...12 slash parity; escaped display closers; LF/CRLF/CR
comment bytes and blank-line boundaries; later-block recovery; Prepend/combining/
ZWNJ/variation scalars; structural/literal boundaries, invalid/overlapping/out-of-
bounds/surrogate metadata; caller-owned snapshot IDs; output caps and controlled
cancellation. A100,000-dollar case yields20,000 correct nonoverlapping spans in
about18msDebug/7msRelease in this component environment. This is not an editor
latency or full rendering-budget claim.

One UTF-16 buffer, sorted interval sweeps and monotonic delimiter indices avoid
suffix rescanning. Source identity/regions/literal exclusions/output limit belong
to the caller. The package preserves raw source body bytes; original and renderer-
decoded TeX stay separate. It has no third-party dependency or rendering/IO path.
Standalone Debug/Release tests are explicitly added to CI; dependency test targets
would otherwise not run with MacDownKit. No production math path switches here.

The first Unicode test oracle uses Foundation's nonliteral text search and cannot
find a dollar token next to a grapheme extender, despite correct lexer output.
It is corrected to literal UTF-16 matching. Three tuple-lint errors are corrected
with a named expected-value structure. Those first failures remain retained.
All316 Compliance controls, inventory and full pinned format/strict lint pass.
The first repository oracle assumed every package had a dependency to reflow;
for this dependency-free package it made no text mutation and failed. Reflowing
the Package container as well preserves every count/URL/unknown/result assertion
and the real-mutation assertion; no parser rule or test is disabled. Failure and
passing run are retained. No native product code runs locally.

Production structural admission, native transport activation, shared Preview/
Export behavior, engine diagnostics/limits, accessibility/navigation and final
visual/release evidence remain required. The unpaired-display recovery and
ambiguous dollar-run choices are deliberate fixture policy before activation.
No issue9 acceptance criterion is closed by this standalone foundation.

The prepared branch also includes PR83's exact style-version correction before
publication. Combined inventory,316 Compliance, full pinned format and strict
lint pass again; app manifest/all24 pins are byte-identical to PR83. Its full
hosted validation/integration must finish first. The standalone package has no
remote dependency, and production consumers remain unchanged.

# Complete injection coverage and explicit inline fresh parsing

When a partial query touches an old capture, its replacement can begin outside
that query. On the prior SwiftTreeSitter1b1c85e9 dependency the minimized default-
policy test loses an inline paragraph for LF, CRLF and CR (six assertions fail).
The final refactored 2,000-edit Unicode-scalar corpus also fails at edit44 on
that original dependency. Its baseline-only test copy omits the new policy
assignment because the previous dependency has no such API; operations and the
strict fresh-highlight comparison remain identical. Both source and failed logs
are retained. The first minimal setup, which queried the parser's broad changed
range, passed the baseline; it is retained as a control rather than described
as a reproduced failure. The failing public partial-query setup explicitly
resolves the changed prefix after applying the edit without automatic resolution.

Expanding only fresh captures is insufficient. The repair expands complete old
captures as well and requeries to a fixed point before retiring ownership. The
coverage-only candidate advances the long corpus to edit1745: root AST and child
ranges equal fresh, but the inline child AST differs and whole resolution cannot
repair it. That second failure is retained separately. The focused architecture
revision introduces default-true LanguageConfiguration.reusesPreviousTree.
The app disables it only for MarkdownInline, preserving the old tree for
invalidation comparison while parsing without reusing it. Runtime and grammar
bytes, constructor signatures and the 8192-unit fallback remain unchanged.

Exact owner SwiftTreeSitter7d2dc87e8b9326062d75bc1ef985f17d28e94da9 passes
36 XCTest cases and 12 Swift Testing functions Debug/Release. The inspected
Foundation/C client fixture passes 36 production regression functions in eleven
suites plus eight XCTest cases. Its final timing-instrumented runs contain one
additional component-only probe (37 functions/twelve suites). All2,000 scalar
edits match fresh highlights. The default-policy minimal regression passes all
three line endings independently of the fresh-parsing policy.

The Release component probe performs100 replace/edit/query operations at each
of1000,4000,8000 UTF-16 units in one Markdown paragraph; exact source and output
are retained. These are component timings under concurrent host load, not full
editor or release responsiveness evidence. The 1 MB/50 ms contract remains open.

Manifest-only Neonbe25e35787585430f0f1ac845ed44c11e7f8150a preserves every
Neon runtime/test byte from baf93c7. Only Neon and SwiftTreeSitter application
lock identities change; all22 other pins and original BSD licences are verified
unchanged. App/vendor manifests, inventory, notices and SBOM agree. All316
Compliance controls, inventory, full pinned format and strict lint pass. The
actual HighlightingTests target compiles with forced resolution. Its first
compile caught the new stress test constructing the main-actor registry from a
nonisolated helper; the failed log is retained, and only registry access now uses the main
actor. The unchanged long corpus runs in an explicitly detached worker with
Sendable configurations, avoiding main-actor starvation of concurrent hosted
native callbacks. Final Debug/Release component runs and target compilation
pass after that executor correction. No production behavior, native assertion or deadline was weakened.

The fixture's #canImport(Highlighting)/#canImport(Neon) paths are excluded locally.
It runs only inspected Foundation/C source, using exact copied production test
bytes and a documented Foundation-only styling adapter. All source and log
hashes are recorded. No local app/helper/AppKit/SwiftUI/WebKit execution occurs.
Full exact-head hosted package/app/CLI CI remains required before merge. Native
EXECUTION_HOLD, accessibility, lifecycle, signing, publication and release gates
remain open. The separate C lexer optimization has not been adopted by this unit.

# Lexer range lookup: qualification and retained baseline failures

At each seek, stock tree-sitter0.25.10 scans included ranges from the beginning.
The owner patch lower-bounds the first range end after the seek byte, then keeps
the existing forward skip, position/chunk/point handling and EOF behavior.
Valid ranges have nondecreasing end bytes. The product diff is14 insertions and
one deletion in lib/src/lexer.c; headers, ABI, grammar and original MIT licence
are unchanged. Exact original base: da6fe9beb4f7f67beb75914ca8e0d48ae48d6406.

Owner runtime5ce80b6f0e29096a5f06826a3ba610c4e89bc255, dependency-metadata
SwiftTreeSitter0beea992c4246f93a122de846c8611c9be19aeb7 and manifest-only
Neonab93bca8cc74af6f5e17eefc7fefa1999726a131 preserve every prior capture,
fresh-inline, client, semantic/paint and buffered-coordinate repair. Swift layer
and Neon runtime/test bytes are identical to PR80's dependencies. All original
MIT/BSD licence texts are verified unchanged. Only three app lock identities
change, with21 other pins unchanged. Inventory, notices and SBOM agree.

The standalone actual-lexer/original-linear reference compares1,624,448 cases
across10,000 range sets: empty/adjacent/gapped ranges, chunk and column state,
byte/point positioning and EOF. Original/candidate pass; candidate ASan/UBSan
passes. Forty-eight original runtime source/header files are checked against
the baseline snapshot; candidate changes only the declared lexer file.

The documented cargo xtask test passes262 cases before/after. A broader
cargo test --workspace passes317 unit cases but5 Rustdoc examples fail with
missing example variables/devgrammar. Identical5 failures reproduce on the
unmodified runtime. Both complete failed logs remain; examples are not disabled
and broader workspace validation is not called fully green.

The original raw-unit corpus can split encodings and fails unmodified runtime
fresh equality at UTF-8 edit115. A distinct valid-scalar corpus keeps boundaries
and also fails unmodified UTF-16LE fresh equality at edit1018. Both fail-fast
oracles, diagnostics and setup errors are retained. A separate all-step collector
compares6,000 edits across UTF-8/UTF-16LE/UTF-16BE. Every old/new-runtime AST,
point, missing-node and query-capture trace is byte-identical. Both return2 for
exactly282 original fresh-tree discrepancies. Sanitized candidate traces match
all output/diagnostics, with no sanitizer finding. This is behavior-preservation
proof; it is NOT6,000 fresh-equality passes. PR80 independently fixes the actual
application path with an explicit MarkdownInline fresh-tree policy and a strict
2,000-edit actual-root/fresh-highlight oracle, unchanged in this unit.

Inspected Foundation/C current application component suites pass41 functions
in12 suites plus8 XCTest cases Debug/Release, including that strict2,000-edit
oracle, all prior client/style controls and75,772 buffered-coordinate cases.
Upstream Swift layer suites pass36 XCTest cases plus12 Swift Testing functions
Debug/Release. Exact selected source hashes and the Foundation-only styling
prefix boundary are recorded; native conditional tails are excluded locally.
The real HighlightingTests target compiles with locked resolution. Inventory,
all316 Compliance controls, full pinned format and strict lint pass.

The retained many-range benchmark has identical trees at all six range counts.
At30,000 ranges its component edit median falls from about1442ms to146.7ms.
It runs under concurrent host load and excludes native editor work; the1MB/50ms
editor requirement remains unmet/unproved. No8192-unit fallback change occurs.
No local app/helper/AppKit/SwiftUI/WebKit runs. Full current-head hosted CI and
PR80 integration remain required before merge. Native EXECUTION_HOLD, release,
rights/source-offer publication and exact-artifact gates remain open. There is
no upstream submission or upstream endorsement.

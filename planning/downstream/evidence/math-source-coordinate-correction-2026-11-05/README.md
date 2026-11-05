# Correct original-source coordinates before publishing source facts

This packet supersedes the earlier source-fact draft's coordinate hold. Canonical
baseline3336e59b includes the shared grammar foundation; production math consumers
remain unchanged. The actual original runtime fails53 coordinate assertions:
Unicode/all line endings, lazy/varying prefixes, paragraph/table header positions,
reference-definition removal, multiline code/HTML and table escaped pipes.
Bounds-only checks also accept wrong-but-in-bounds coordinates, so a source-owner
fix is required rather than a guessed projection or weakened test.

Qualified owner pins are recorded in manifest.json. Only five C runtime files
change;162 other original files and complete COPYING remain exact. All87 Swift
Markdown library source files, original LICENSE and NOTICE remain exact; its
manifest pins the corrected C owner. Prominent downstream change notices and
exact base/source manifests are retained. Public opaque-node APIs stay unchanged;
the internal layout gains sparse source segments. Inline parsing finishes before
coordinates are corrected, preserving delimiter/reference calculations.

668 original C API controls pass normally, with AddressSanitizer and with
UndefinedBehaviorSanitizer. Unnormalized original outputs pass670 CommonMark,
26 regression,30 GFM and16 smart-punctuation cases. All299 upstream XCTest plus6
source-coordinate Swift Testing functions pass Debug/Release. One old snapshot
expected a brace at column3 although its authored byte is at1: only those exact
expected coordinates change, and a separate authored-byte oracle proves them.
Initial compile failures,53 old-runtime failures, initial HTML end-column failures,
the unchanged snapshot failure and a missing-extension setup failure remain
retained alongside corrected results. No assertion, timeout or rule is disabled.

9054 deterministic generated actual Markdown cases have identical non-position
AST content and formatted Markdown. Actual HTML parsing enables source positions
on both runtimes: removing only generated numeric data-sourcepos attributes leaves
all other output bytes identical; raw position attributes change in54 cases.
All9054 complete candidate AST/format outputs match under AddressSanitizer with
no finding. The generated source corpus, actual probe source, output receipts,
per-case hashes and source-owner patches are retained by digest.

The exact application MarkdownEngine sources/tests run in a Foundation/C/CryptoKit
fixture against the immutable remote owner pins and unchanged Yams pin. All159
functions/22 suites pass Debug/Release, including original worker/queue/cancellation,
YAML, depth, source identity, block repairs and unchanged timing controls. The new
multiline-link test first reproduces three overbroad prefix ranges containing
an authored title; the projection now emits only parser-positioned whitespace/
quote prefixes. NUL sanitization and unsupported coordinates/depth fail closed
without changing source. Every fixture/production file is byte-identical; full
input hashes and the three-pin lock are retained. The actual locked application
MarkdownEngineTests target compiles. Exactly two of24 app pins change;22 remain
byte-identical, including the qualified Textual/Neon/tree-sitter owners.
Inventory,316 Compliance and full pinned formatting/strict lint pass.

The earlier PR85 head56d72a6c complete hosted run42002905284 passed, but cannot
qualify these newer source/pins. Retain it as superseded evidence and require a
fresh exact-head full run before merging. No AppKit/SwiftUI/WebKit/product CLI,
signing key or owner data executes locally. No upstream acceptance, source-offer
publication, production Math/Preview/Export activation, whole-editor1MiB/50ms,
VoiceOver or final native/Release acceptance is claimed.

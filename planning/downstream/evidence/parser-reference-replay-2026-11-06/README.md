# Parser-consumed reference replay qualification

The old line-based Preview extractor loses 16 of 18 real-parser target/title
controls. The parser now retains the actual consumed logical definition syntax
and actual resolved link/image uses; no URL/title serialization or label
normalization is introduced. Original source-coordinate owners remain parents.

C API: 742 checks pass normally, with AddressSanitizer and with UndefinedBehaviorSanitizer, including 74 new allocator/lifetime/type/opaque-extension checks.
Original exact strict fixtures: 670 CommonMark, 26 regression, 16 smart punctuation and all 30 CMake-configured GFM cases pass. Node remains 216 bytes; the 40-byte link fits the existing 40-byte union.
Swift Markdown: all 299 XCTest and 10 Swift Testing functions pass Debug and Release. Document mutation drops parser-only metadata promptly.
Complete AST/source-position/format output and complete HTML including data-sourcepos are byte-identical to qualified abfafecc/2a5339b8 on 9,054 deterministic cases. The actual AddressSanitizer execution of the exact AST corpus is identical with no finding.
The exact first-party Foundation MarkdownEngine fixture passes all 176 tests/24 suites Debug and Release; default 10MB Release is 3.220 seconds, a package baseline rather than whole-editor latency.

Retained setup failures: original Python program splitting a path with spaces; incorrect extension flags (27/3); unsupported footnote CLI flag; ASAN detect_leaks unsupported on macOS; accidental expanded 27,216-case ASAN invocation failed exact-count comparison despite no sanitizer finding. Correct invocations preserve original source/assertions. See raw logs and sanitizer-invocation-notes.txt. The first lifetime review draft is retained as before-lifetime-review-node.c.

Native marker reference replay, immutable application pin adoption, complete app/CLI CI and production activation remain separate next gates. This packet establishes component behavior, not native owner acceptance, independent rights review or a release.

## Native reference-scope regression and guard

The actual Foundation/C parser proves a 12-link whole document leaves the last
equation unlinked; fresh block replay resolves it. Hosted before run 42084519940
on 2b91b0dd confirms the equation acquired the 8,001-byte URL: the original no-link
assertion fails. All original 37 functions pass. Three additional setup failures
come from the initial fixture choosing a math-looking definition key before its
actual block; select the block-local occurrence then offset it to original source.
The prior 42084147757 never ran tests: the lint-refactored named helper still
returned its former tuple; 2b91b0dd corrects that wrapper. Both complete logs stay.

The guard now checks every actual native link/image URL against forward-projected
original ranges and resolved destinations, with separate roles. It denies wrong,
foreign, overlapping and unpositioned authority even without equation markers.
Failure returns the whole original block visibly. Image facts preserve original
resource targets while keeping image contents literal to math. Exact Foundation
fixtures pass 177 MarkdownEngine functions Debug/Release and 13 input/authority
functions Debug/Release. An initial pure fixture omitted its macOS platform and
failed compilation before tests; the fixture now declares the product's macOS26
minimum, without availability guards or source/test changes.

All 45 actual native functions compile only locally; source plus all six application
pins are verified. Full strict lint and pinned formatter pass 1,410 files. Hosted
execution of the guarded 45 functions is the next gate; production is not switched.

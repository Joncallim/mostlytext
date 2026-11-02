# Markdown scanner safety backport — 1 November 2026

## Owner summary

Prevent a deeply nested Markdown document from overrunning the syntax scanner's
serialization buffer or aborting the parser. This is a safety correction in the
vendored highlighter grammar, not a claim that #203's 50 ms budget is met.
Editing and MarkdownEngine rendering retain authored bytes and their existing
owners. No application or native UI test is launched for this unit.

## Baseline, source and decision

Master 15c0fae2 and integration 9de81f5f vendor tree-sitter-markdown v0.5.3,
commit f969cd3ae3f9fbd4e43205431d0ae286014c05b5. Its block scanner blob
fda19bd1204f01bb6c4cf5394aa13d608fe8ef46 exactly matches the parent of upstream
PR 279. The local isolated C control parses 250/254 nested quotes, then aborts
at 255 with the tree-sitter serialization-length assertion. The first ASan
invocation failed before parsing because leak detection is unsupported on macOS;
that attempt is retained separately and is not counted as a reproduction.

Backport the exact scanner changes merged upstream on 22 October 2026:
PR commit c113d7bb568aab992f161b448ae98079de3482b5 bounds new block openings and
serialization; PR commit 66d882592ad7cbb9847ed16170d2ae07da8e324b replaces invalid
ctype classification of full code points and emits the checked ordered-list
marker variant. Use the exact final upstream scanner blob, not a re-created
algorithm. The integrated upstream result is commit
38dc6f5297551f070d15a33fda3da89f01863a04, block-scanner blob
e8d87eec1f8f6dbddd987df43097195e8d790c78. Other parser, scanner, query,
wrapper and dependency bytes stay put.

Upstream authority: https://github.com/tree-sitter-grammars/tree-sitter-markdown/pull/279
and https://github.com/tree-sitter-grammars/tree-sitter-markdown/issues/243 .

## Behavior, ownership and limits

At the scanner's serialization capacity (254 open blocks with four-byte enums),
additional block markers are highlighted as text. This deliberately bounded
syntax fallback does not reject opening/editing/rendering the document and does
not rewrite source. The serialize clamp is a backstop; normal scan transitions
keep the complete state representable. Ordered-list classification uses ASCII
bounds instead of passing arbitrary Unicode code points to isdigit.

Record the MIT upstream patch and exact source/digests in the vendored README
and compliance inventory/notices/SBOM. Do not call the scanner byte-identical to
the v0.5.3 release after this change. Do not change Package.resolved or weaken
performance ceilings/known-failure handling.

## Verification and completion boundary

Retain direct exact-sized-buffer ASan controls before/after, full-parser depth
controls, normal/boundary/deep nesting, list/Unicode fixtures and incremental
versus fresh signatures including node ranges. Run locked focused package tests,
Release builds, source compliance and exact hosted checks. Bound subprocess RSS
and wall time. A complete parse must cover all input bytes, including fallback.

Independent integration review and actual Release editor/native acceptance are
still required. A passing safety backport cannot close #203, #459 or #115; the
O(n) Markdown reparse, UI behavior and exact release-candidate gates remain open.

## Resumed verification

The focused locked package run passed 36 tests in seven suites, including the
new scanner regressions and existing parse, injection, registry and tree-reuse
controls. The receipt in
`CORTANA-Builds/resume-20261101-scanner-package/receipt.json` records the command,
source digests, exit 0 and unchanged inputs. The new controls compare full node
structure, byte/point ranges and incremental/fresh parses, and check normal
ordered lists, paragraph continuation and Unicode. No application was launched.

Source compliance passes with zero unverified items. Release compliance still
reports the same seven unrelated D2/Mermaid/theme/Graphviz findings; none was
waived. Generated notices and SBOM record the patched scanner separately from
the unchanged v0.5.3 grammar. SwiftFormat and strict SwiftLint pass for the new
test file. Release application and test-target compilation are pending.

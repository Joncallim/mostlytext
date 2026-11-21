# Issue #18: bounded paragraph lookup during a large Markdown edit

## Scope and observed failure

The production mounted-display measurement on source `8853235f` (product
source equal to main `5e15b8c6`) took **239.347 ms** from input to bitmap
readback for its first 1,060,415-byte Markdown word edit. The 50 ms product
target failed. The exact [hosted run](https://github.com/Joncallim/mostlytext/actions/runs/44937958364)
recorded 47.246 ms to the storage event, 190.839 ms until `insertText` returned,
0.641 ms in the local parse, and 187.035 ms from parse request to publication.
The latter interval includes main-actor wait while `insertText` is synchronous.
The sample placed eight main-thread stacks in `MarkdownSectionCache.paragraph`
and `ts_node_child`, but its aggregate samples cannot assign the complete
239 ms delay to this lookup.

## Product change

The old `paragraph(in:overlapping:)` materialized and filtered every child of
the selected section on each pre-edit proposal. A top-level heading's section
can own thousands of paragraphs. The new lookup uses tree-sitter's indexed
byte-range descendant query, converts the UTF-16 edit to the parser's UTF-16LE
byte offsets, then accepts only a direct paragraph child of the selected
section. Uncertain and cross-section ranges still return nil, leaving the
existing heading or deferred full-parse path in charge. The ordinary selected
paragraph is passed to admission once rather than looked up again.

The new direct regression covers a Unicode offset, direct paragraph, heading,
nested child section, and cross-paragraph range. The existing 1 MiB rich-prose
oracle still checks seven edit cases, including first/middle/end, deletion,
word boundary, and replacement shrink/grow. This change does not alter the
parser, storage, paint, or timing boundary.

## Reproducible local before/after

On macOS 26.5.1 / Xcode 26.6, with the same new 2,000-selection test and
`swift test -c release --filter MarkdownSectionCacheRichProseTests.boundedHeadingAndInlineEditsMatchFullParse --no-parallel --force-resolved-versions`:

| Source under test | First selection | 2,000 selections | Result |
| --- | ---: | ---: | --- |
| Main `5e15b8c6` lookup, temporarily restored into the worktree | 0.397 ms | 536.363 ms | Fails the new 300 ms selection ceiling |
| Changed lookup and single admission | 0.085 ms | 97.421 ms | Passes |

The baseline source was restored only for that run, then all changed files
were restored. The baseline failure is preserved in
[`baseline-release.log`](evidence/issue18-paragraph-lookup-2026-11-22/baseline-release.log)
(SHA-256 `ae71698355292c37cace4df24c36fa9e384ca3686076c984cc12e8fc9b0e2bb3`).
The changed six-test/two-suite Release selection passes in
[`changed-release.log`](evidence/issue18-paragraph-lookup-2026-11-22/changed-release.log)
(SHA-256 `1dbb1a166839d7fd5f3856fcfc1c255f3e14aef4b19eac371e65c9282be312c3`).
Targeted strict SwiftFormat, SwiftLint, and `git diff --check` pass.

The cold-call gain is approximately 0.3 ms in this local fixture. It is a
bounded synchronous edit-path improvement, **not** proof of the 50 ms
input-to-visible-paint target or a resolution of the hosted 239 ms result.
Keep #18 and its dependent #6/#8 performance rows open. A hosted same-head
mounted-display run should remeasure the complete path before merging.

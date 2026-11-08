# Issue #18: Markdown parse-window feasibility probe

## Owner summary

Large Markdown files still incur a near-whole-document parse on each edit even though styling is viewport-prioritised. This parser-only spike asks whether a small, complete Markdown region could produce the same visible colours as a fresh full parse. On twelve edited 1 MiB fixtures, eleven oracle-selected windows produced exactly the same visible root, inline, and combined query captures. Removing a fence opener made the affected root region extend over 608,000 UTF-16 units, so the spike stopped that case. The result is feasibility evidence for ordinary bounded regions, not a shippable parser design: the oracle still parses the entire document after every edit to discover the region.

No production highlighter, grammar, parser pin, runtime limit, or UI path changes in this spike.

## Baseline and method

- Baseline: `main` at `ffe692feef9c7c8f45ccd2dea1f88e31115aeae6`. The current `GrammarRegistry` deliberately disables old-tree reuse for `markdown_inline`; `MarkdownTreeReuseTests` records that the block grammar reuses almost no sections. Neon's viewport priority therefore bounds styling, not the root parse.
- The test builds each source to exactly 1,048,576 UTF-8 bytes before one edit. The edited source may differ by the replacement's byte length. A repeated plain heading section surrounds a single edited island near the middle, except for frontmatter at byte zero.
- A **fresh full parse after the edit** is the oracle. Binary search over its ordered top-level children selects every root child overlapping a 192-unit visible span beyond the changed text, with 64 units of leading context. The selected children's outer range is independently parsed from a UTF-16 substring.
- The probe compares sorted capture **names and visible-clipped UTF-16 ranges**, rebased to document coordinates. It compares root Markdown captures, the `markdown_inline` sublayer's captures, and the fully combined language-layer captures. The combined check also covers available fenced, HTML, and frontmatter injections.
- A selected region exceeding 65,536 UTF-16 units stops before window parsing. This is only the spike's diagnostic bound, not a proposed product threshold. A mismatch also fails its case and prints the first differing captures. The structural fence edit is a pinned negative control.
- The test uses `LanguageLayer` and `GrammarRegistry` as pure parser objects. It creates no `NSTextView`, `NSWindow`, Neon highlighter, owner document, or product process.

## Release measurement

Command: `swift test -c release --force-resolved-versions --filter MarkdownViewportWindowProbeTests --no-parallel -j 6` from `MacDown2/Packages/MacDownKit` on the local Apple silicon Mac. Durations below describe this parser harness, including query capture comparison in the window duration. They are not app keystroke, main-thread, or native acceptance measurements.

| Edit family | Cases | Result | Window UTF-16 units |
|---|---|---|---:|
| Fenced code | content edit; opener deletion | content parity; opener stopped | 230; 608,630 |
| Lists and quotes | nested-list content; list marker; quote marker | parity | 224–229 |
| HTML | text; opening tag delimiter | parity | 223–226 |
| Frontmatter | YAML value; first delimiter | parity | 228–234 |
| Line endings | mixed CR/LF/CRLF text; CR to CRLF boundary | parity | 223–283 |
| Unicode inline | composed/decomposed text and emoji replacement | parity | 268 |

Across two local Release runs, the fresh full oracle took roughly 1.64–2.13 seconds for the eleven matching cases, binary root-boundary lookup 28–46 microseconds, and window parse plus capture comparison 0.24–0.43 milliseconds. The opener-deletion case's oracle took 0.46–0.54 seconds and selected a 608,630-unit root region, around 58% of its edited document. All cases had 1,048,576-byte starting sources. These are local observations, not a stable performance budget. The query setup/cache state and fixture shape affect the numbers.

The matching Debug command without `-c release` also passed all twelve cases in 34.99 seconds on the same Mac. Its full-oracle parses took 2.68–3.40 seconds, and its window parse and capture comparison took 0.92–1.32 milliseconds. The Debug test stays below its three-minute test limit on this machine; CI runner timing remains unmeasured.

## Decision and remaining proof

The spike establishes that context-complete root windows *can* preserve visible capture parity for the eleven exercised edits. It also demonstrates an unbounded structural edit. It does **not** establish a way to identify those windows from the pre-edit tree without reparsing the whole source. In particular, the full post-edit oracle is excluded from the quoted window duration and cannot be used in the typing path. The selected windows come from a highly regular heading corpus; arbitrary long paragraphs, nested structures, and back-to-back structural edits remain unproved.

Issue #18 should remain open. Before production work, prove a bounded boundary-discovery and invalidation method using only pre-edit state, then rerun exact root, per-inline-region, and combined capture parity on adversarial 1 MiB edits. A structural edit must have a specified safe outcome when context grows beyond the bounded region. Only after that proof should the editor integration address stale async results, viewport motion, text-version ownership, and Release app-path responsiveness. Native UI acceptance remains a separate gate.

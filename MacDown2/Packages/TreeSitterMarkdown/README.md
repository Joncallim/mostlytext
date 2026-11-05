# TreeSitterMarkdown (vendored)

Block and inline Markdown grammars used for editor syntax highlighting.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/tree-sitter-grammars/tree-sitter-markdown |
| Release | `v0.5.3` |
| Commit | `f969cd3ae3f9fbd4e43205431d0ae286014c05b5` |
| Licence | MIT, Copyright (c) 2021 Matthias Deiml (`LICENSE`, copied verbatim from that commit) |
| Verified | 2026-09-28, by comparing the Git blob hash of every vendored file with the upstream history |

Every parser, header and injection-query file, and the inline scanner, is
byte-identical to the upstream file at `v0.5.3`. The block scanner carries the
exact upstream safety backport described below:

| Vendored file | Upstream file |
|---|---|
| `Sources/TreeSitterMarkdown/src/parser.c`, `scanner.c`, `tree_sitter/*.h` | `tree-sitter-markdown/src/…` |
| `Sources/TreeSitterMarkdownInline/src/parser.c`, `scanner.c`, `tree_sitter/*.h` | `tree-sitter-markdown-inline/src/…` |
| `Sources/TreeSitterMarkdownResources/queries/injections.scm` | `tree-sitter-markdown/queries/injections.scm` |
| `Sources/TreeSitterMarkdownInlineResources/queries/injections.scm` | `tree-sitter-markdown-inline/queries/injections.scm` |

The generated `parser.c` files declare tree-sitter `LANGUAGE_VERSION 15`.

## Local modifications

The block `Sources/TreeSitterMarkdown/src/scanner.c` is the exact upstream blob
`e8d87eec1f8f6dbddd987df43097195e8d790c78` at merge commit
`38dc6f5297551f070d15a33fda3da89f01863a04` from
[upstream PR 279](https://github.com/tree-sitter-grammars/tree-sitter-markdown/pull/279),
merged 22 October 2026. Its SHA-256 is
`25b9020542e35492bde8f1b9ae3fe498a29f3c5130c40c8ffdbfb67e7882acf1`.
It bounds block state to the tree-sitter serialization capacity and classifies
ordered-list digits with ASCII comparisons. Beyond that capacity, additional
block markers are highlighted as text; authored bytes remain unchanged. The
parser and queries retain the v0.5.3 grammar. This backport does not address the
Markdown incremental parsing performance tracked in application issue #203.

The two `highlights.scm` query files also differ from upstream. They were
rewritten to emit this app's canonical capture names (for example
`@text.title` became `@markup.heading`, `@text.literal` became `@markup.raw`
and `@punctuation.special` became `@punctuation`). Two pattern changes go with
the renaming: heading captures cover the whole `atx_heading`/`setext_heading`
node rather than only its inline text, and the separate heading-marker and
emphasis/code-span delimiter captures were removed. Run `diff` against the
upstream files for the exact change.

Upstream marks both query files as originating in
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
(Apache-2.0) and redistributes them under its own MIT licence. The release
notices include the nvim-treesitter Apache-2.0 notice as well, as a
conservative attribution.

The Swift wrapper files (`*Resources.swift`) and `Package.swift` are
first-party. The manifest pins the same maintained SwiftTreeSitter fork as
MacDownKit and Neon for a single canonical dependency graph; this does not
change the vendored C grammars, scanner or queries.

## Updating

Replace the files from a single upstream release tag, re-run the blob-hash
comparison, and update this table and `compliance/inventory.json` in the same
change. `python3 compliance/tools/compliance.py check` fails if the recorded
digests and the vendored bytes disagree.

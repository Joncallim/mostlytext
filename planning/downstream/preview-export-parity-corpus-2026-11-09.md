# Current Markdown Preview and export parity checkpoint

## Owner summary

MostlyText uses two Markdown renderers: native Preview uses parsed source blocks and Textual, while HTML export uses cmark-gfm. This checkpoint compares the same small source corpus on both paths so an ordinary renderer change cannot silently drop core structure. It also records where the two surfaces intentionally follow different raw-HTML policies. It does not certify visual parity, derived math/diagram rendering, or the complete issue #11 acceptance criterion.

## Baseline and comparison boundary

Baseline: `main` at `ffe692feef9c7c8f45ccd2dea1f88e31115aeae6` (9 November 2026). The package test `PreviewExportParityCorpusTests` parses exact source through `ParseEngine`, takes the same top-level source slices used by native Preview through `PreviewBlock.blocks(from:text:)`, and passes those slices to `PreviewMarkupParser`. The slicer omits a block's terminal line ending; the test checks those actual slices. It separately prepares ordinary embedded-style HTML with `ExportService.prepare`. No browser, native SwiftUI view, PDF printer, app menu, document file or network access is part of this test.

The compared expectations are structural, not a byte-for-byte comparison between HTML and an attributed string:

| Source case | Preview-side observation | Export-side observation |
| --- | --- | --- |
| GFM table with Unicode | table block and Textual table intent | table/header/cell HTML and Unicode text |
| checked and unchecked task items | parser retains each task state; Textual retains list intent and item order | checkbox markup and ordered item text |
| ordered lists starting at 4 and 7, including a quoted list | source blocks retain the authored start numbers; Textual retains ordered-list intent | both `ol` elements retain their authored `start` values |
| strikethrough and autolink | inline strike intent and resolved link URL | `del` element and link destination |
| repeated Unicode headings | two level-one blocks, native anchor fragments, Textual heading intent | two visible heading elements and text |
| front matter | YAML is removed from Preview source blocks | YAML becomes title metadata, not body text |
| nested quote/list and fenced code | quote/list/code source structure and literal code text | corresponding quote/strong/code HTML |
| authored raw HTML | Textual presents the tags as literal source text | ordinary HTML export preserves authored markup |

The raw-HTML difference follows the existing E12 policy: ordinary HTML preserves authored HTML, self-contained HTML rejects it, while the tested Textual parser returns authored tags as literal source text. The test does not make a security or visual claim from a string comparison.

The 9 November follow-on at baseline `87552f7d` adds a non-one ordered-list case. It checks the authored starts at the native Preview source-block boundary, Textual's ordered-list intent, and both emitted HTML `start` attributes. The attributed string does not establish the numbers actually painted by the native list view; that remains part of visual acceptance.

## Remaining work for issue #11

- A checked task's actual native checkbox appearance and click/accessibility behavior still need visual/native acceptance. Parser state plus export markup alone do not establish that experience.
- Export heading identifiers need the emitted-heading DOM and navigation integration checks already owned by the heading pipeline; the small corpus checks native fragments and exported heading text, not identical DOM IDs.
- Math, Mermaid, D2, Graphviz, TOC and other derived contributions use separate asynchronous source-identity and renderer paths. Existing feature tests remain necessary; a complete current parity corpus must add final prepared-source/Preview/PDF comparisons and deliberate-difference records for these cases.
- Browser/PDF layout, accessibility, image/resource loading, print colors and exact release-candidate UI export are outside package tests and remain native acceptance gates.

The issue #11 parity checkbox stays open until those gaps are reconciled on the final candidate.

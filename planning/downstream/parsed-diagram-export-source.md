# Use parsed code text for exported diagrams

A quoted or list-nested diagram should receive its authored diagram text,
without Markdown container markers. The current export scanners recover text
from physical source lines and can retain quote/list prefixes or mistake a
content line for a closing delimiter. Use the existing parser's decoded code
body instead of inventing another container parser. Preserve the original
source range for replacement and navigation.

## Baseline and scope

Main is `a95ff1fc4498e925eb1582fa6eb9e7fab5baf5ad`. MostlyText #11 owns the
export half of #17 F06 and final F07 parity. Read the current #118 handoff,
EPIC_STANDARD and RELEASE_HARDENING. Swift Markdown 0.8.0 is already pinned;
ParseEngine alone converts its code nodes into immutable MarkdownBlock values.
All three export scanners currently discard that parsed literal and re-slice
physical lines through the shared legacy delimiter helper. Existing quote tests
often assert only fence count, not exact renderer input.

## Interface and behavior

Add optional `codeBlockContent` to MarkdownBlock, defaulting to nil for existing
manually constructed models. During the existing parser conversion, retain
CodeBlock.code after removing at most its one terminal LF. This keeps the
scanners' established no-final-terminator convention while preserving genuine
internal/trailing blank lines. Parser normalization is for derived renderer
input only; never change source text, encoding, source range or source identity.

The Mermaid, D2 and Graphviz export scanners prefer this parsed value, including
an empty string, after their existing language/range validation. Unbound manual
models retain the existing helper fallback. No renderer, parser dependency,
Preview adapter, UI, timeout, resource grant or held consumer activation changes.
The metadata is an immutable optional String, carried with the existing node;
no second parse, regex container scan, asynchronous state or new dependency.
It retains code text in snapshots; broad app memory/performance acceptance
remains open and must not be inferred from this source fix.

## Verification slices and boundaries

1. Before editing production, run a source-identical owned Foundation-only
   parser/scanner fixture with the pinned local Swift Markdown/cmark/Yams inputs
   and golden scanner tests. Preserve actual failures and hashes. The fixture
   imports no AppKit/WebKit/SwiftUI, does not launch an app or change owner data.
2. Implement the optional payload and three scanner consumers. Cover all three
   languages, nested quote/list/combined containers, same-line list fences,
   unterminated blocks followed by siblings, genuine `>`/indent/backticks,
   blank/empty bodies, longer/tilde fences, front matter and Unicode/CRLF/CR.
   Assert exact renderer input and original UTF-16 ranges/source identity.
3. Run the identical goldens on the fixed source, relevant existing parser/
   scanner suites, Debug and Release source fixtures, format/strict lint,
   Compliance/inventory and hosted complete locked package/app/CLI/build tests.
   Preserve any unrelated actual failures rather than retrying them into a pass.
4. Review and merge only qualified exact source, reconcile #11/#17 evidence and
   live issue counts, and preserve native/Preview/export-parity/whole-issue gates.

Stop on parser/source identity disagreement, golden results requiring a guessed
container grammar, unrelated dependency/API changes or any need to weaken an
assertion/budget. Preview remains unchanged: nested Preview presentation and
final Preview/Export/native parity need their original separate evidence. This
unit resolves export input extraction, not all F06 or the entire export issue.

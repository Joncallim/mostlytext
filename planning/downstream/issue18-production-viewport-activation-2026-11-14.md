# Large Markdown viewport activation

## Decision

`SyntaxHighlightStore` now requests the existing bounded viewport owner when it builds a highlighter. This affects Markdown documents above the 8,192 UTF-16-unit full-highlight threshold **only when the editor is mounted with a usable viewport**. Other languages and unmounted editors retain the existing full, reduced, or plain behavior. The direct `NeonSyntaxHighlighter` initializer keeps its opt-in default for isolated callers and tests.

## Authority and fallback

- `NeonSyntaxHighlighter.startViewport()` requires Markdown, a mounted scroll view, an unused pre-edit observation slot, and current storage; failure leaves reduced mode in place.
- Production viewport admission is capped at 1,100,000 UTF-16 units, just above the qualified 1,048,804-byte fixture. An edit crossing the cap retires its parser and clears presentation after the storage callback; a subsequent shrink into the admitted range can restore the viewport owner after the established idle delay. Larger inputs retain reduced highlighting until their parse and memory costs are measured.
- The storage gate invalidates parse authority at the actual edit. A plain-word edit can select one bounded cached section. A structural edit rejects that window and schedules a fresh off-main parse. Publication checks the storage generation and bound storage identity.
- The painter queries a bounded visible UTF-16 range through Neon's public TextKit styler. Teardown clears the observer, storage callback and painter. Theme, font and language changes invalidate or replace the viewport owner.

## Qualification boundary

The mounted integration test now constructs the highlighter through `SyntaxHighlightStore`, checks both bounded and structural edits, and verifies theme/language/teardown ownership. The opt-in 1 MiB Release benchmark measures the same production store route; its reduced-mode arm remains a direct control. A successful hosted timing test is a component measurement. The 50 ms full product event-to-paint budget, IME/undo/external-reload stress, exact installed Release behavior, and owner-native acceptance remain separate gates in issue #18 and issue #19.

At this source, local Debug and Release mounted integration both pass 3/3, including over-cap transition, reopen refusal and shrink/idle restoration; Release reduced fallback lifecycle passes 6/6. The local 1,048,804-byte production-store viewport benchmark selects and matches twelve bounded edits and performs one initial full parse. Hosted exact-head CI and measurement remain required before integration.

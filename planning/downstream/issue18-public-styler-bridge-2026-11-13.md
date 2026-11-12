# Issue #18: public styling seam for large Markdown

## Owner summary

Current MostlyText drops Markdown syntax colors above 8,192 UTF-16 units. A
separate test proved that a cache of parsed Markdown sections can survive 14
ordinary edits in a 1 MiB fixture, but that cache has no route to the editor's
actual painting code. This probe checks one missing connection: a mounted
TextKit 2 editor can accept semantic tokens through Neon's **public**
`TextSystemStyler` and `TextViewSystemInterface`, then move the styled range
after an edit. It does not turn on large-file highlighting.

## Baseline and result

- Baseline: `main` `f81e92d2d591815aadc446403a6720af0bec1c1a`.
- The production `NeonSyntaxHighlighter` creates a `TextViewHighlighter` whose
  parser tree and edit coordination are private to Neon. Its size policy
  currently enters reduced/plain mode above 8,192 UTF-16 units. The editor's
  storage gate sits ahead of the Neon delegate and can refuse that parser work.
- The existing `MarkdownSectionCacheSequentialProbeTests` retains root,
  inline and combined capture parity for 14 ordinary edits. Its selection
  admits only a bounded plain-word window and refuses structural edits.
- `PublicStylerBridgeProbeTests` mounts a real `EditorTextSystem` in an AppKit
  window, supplies a token through public Neon types, checks TextKit 2's
  rendering attributes, inserts text before the token, tells the public
  styler about the edit and verifies the token's new range and unchanged
  document text. The selected local Swift Testing result is one pass. No
  installed app was run.
- `MarkdownSectionCacheSequentialProbeTests` now also feeds **actual** root and
  inline captures from its 1,048,576-byte Markdown fixture through the same
  public styler. Four bounded word replacements alternate between two sections
  and return to each after a viewport move. Each updates the cache and mounted
  editor, invalidates only the visible range, paints exactly the capture-covered
  offsets in that range, and matches a fresh full-parse capture oracle. The
  selected local run passed this mounted test after 14.241 seconds. The final
  three-test selection passed all three in 60.145 seconds, including the
  original 14-edit cache oracle and synthetic-token mounted bridge. Strict
  SwiftFormat, SwiftLint and whitespace checks pass. This checks a narrow
  presentation connection; it does not qualify a production adapter, a stale
  result race, structural edits, or the whole-editor latency budget.

## Production ownership decision

The next production slice can put a **separate Markdown-only token provider**
behind `TextSystemStyler<TextViewSystemInterface>` when the current size policy
would otherwise enter reduced/plain mode. It need not reach into Neon's
private `TextViewHighlighter` or silently change other grammars. Keep the
existing Neon path for documents below the cutoff until the alternative has
correctness and performance evidence.

The public styler does not parse, own storage edits, or cancel work. A
production adapter must therefore own all of these boundaries explicitly:

1. Obtain the old source/window and edit geometry from an editor pre-mutation
   hook or retained immutable snapshot. `NSTextStorageDelegate` receives
   `willProcessEditing` **after** characters have changed, so the existing
   storage gate alone cannot supply old source bytes. Use it to publish each
   post-edit notification once. Keep TextKit styling out of `processEditing`
   and never apply a style to a different revision.
2. Keep parsed section trees and their UTF-16 offsets together. The bounded
   plain-word path may update only a proven local window. A structural edit,
   paragraph over the bound, IME composition, unsupported source or uncertain
   section boundary must fail closed to a deferred full parse, not keep stale
   colors.
3. Freeze text for background parsing without reading mutable `NSTextStorage`
   off the main actor. An old parse result may be discarded; its token set
   must never paint over a newer edit, teardown or language/theme change.
4. Convert root/inline query captures into the same token names/ranges and
   precedence as the current Neon path. Bound TokenApplication painting to
   the invalidated visible range and preserve selection, marked text, undo,
   authored attributes and the source bytes.
5. Give full parse, parse queue, memory, viewport paint and main-actor work
   separate measured ceilings. Count the complete keypress-to-settled-color
   path in Release on a 1 MiB mixed Markdown fixture; do not use the local
   synthetic-token result as the 50 ms/8 ms budget proof.

## Next qualification

Extend the mounted capture probe across repeated edits and viewport moves.
Compare rendering-attribute runs with a fresh full-parse oracle after each
edit. Include a held stale result, a structural edit,
Unicode/CRLF geometry, IME/undo and teardown negatives. Only then integrate a
production adapter under the size policy and run complete Release/hosted/native
measurements. This probe adds no product UI or user-visible promise by itself.

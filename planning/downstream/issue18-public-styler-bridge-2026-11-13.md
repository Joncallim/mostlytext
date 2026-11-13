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

### Current-main edit boundary (13 November 2026)

At main `0035839e`, `EditorView.Coordinator.shouldChangeTextIn` already sees
the old range and replacement string before AppKit changes storage. It records
that geometry for the line index; its following `textDidChange` publishes the
post-edit index update. `HighlightingStorageGate` receives the same ordinary
character edit after mutation, ahead of Neon's private delegate. The existing
`EditorTextSystem.textChangeObserver` is already used by search, so a large-file
highlighter must not take ownership of that single callback or turn a routine
keystroke into a full `textView.string` copy.

A narrow EditorCore pre-edit observer can pass old coordinates and replacement
length while the live `NSTextStorage.mutableString` is still unchanged. The
Markdown adapter must use that source only within the synchronous callback to
select and copy its bounded local window; it cannot retain the mutable string
as an immutable snapshot. The storage gate can then pair one post-edit range,
length delta and editor revision with that pending selection. If no matching
pre-edit event exists, or a nested edit vetoes/replaces it, the candidate is
discarded and a deferred full parse is scheduled. Undo/redo bypass the
coordinator hook; programmatic reload, composition and teardown likewise take
the full-parse or plain fallback path. The current 8,192-unit reduced mode
stays in production until this pairing and mounted styling are qualified.

This decision avoids a cross-module import from EditorCore to Highlighting:
EditorCore exposes only edit geometry through an observer; Highlighting owns
the parser cache, revision pairing, background work and public Neon styler.
The next implementation slice must prove callback ordering and failure
behavior in a mounted editor before it can replace the reduced-mode path.

The first observer slice now compiles every package test target and its
mounted `EditorLineIndexWiringTests` control checks that a normal replacement
sees the old live UTF-16 source, including a surrogate pair and CRLF, before
AppKit mutates it. A second gate control records the actual post-mutation
`NSTextStorage` range, UTF-16 delta, new length and new text; its focused local
run passes 1/1. These two observations are intentionally separate. A
production cache must compare them and refuse a stale candidate when an
assist vetoes an edit, nested editing changes its geometry, or a programmatic
path skips the pre-edit hook. No cache or large-file painting path is active.

The next isolated pairing slice adds `MarkdownEditPairing`, whose selector runs
synchronously against the live old `NSString` and must return a bounded,
owned candidate. The pairer retains only that candidate, old geometry,
replacement and old UTF-16 length. After TextKit edits, it admits the candidate
only if the actual range, delta, new length and replacement substring agree.
It refuses replacement strings above 65,536 UTF-16 units before selecting a
candidate, leaving large paste/reload work to the deferred path.
Multiple pre-edit proposals before one post-edit notification are ambiguous
and are rejected. Any rejection clears the candidate; the caller must defer a
full parse or stay plain. The real `EditorView` pre-edit observer and storage
delegate are exercised together, alongside independent veto/nesting/undo-like
unobserved negatives. Four focused local Debug tests pass after the complete
package-test bundle compiles. This does not connect the section cache or paint
tokens; it only establishes a fail-closed admission boundary for that work.
An unsupported first proposal still occupies its edit cycle: a later nested
proposal cannot become a candidate merely because the first selector returned
nil. The negative control and mounted controls pass together in the four-test
selection; strict SwiftFormat and SwiftLint pass.
The eventual parser result still needs an independent editor-revision guard
before painting; geometric pairing alone does not give async result authority.

The section cache has now been moved from test support into the Highlighting
source target without attaching it to the editor. Its selection refuses an
invalid viewport; replacement refuses mismatched window geometry, content
length or delta before changing cached trees. It stores immutable, Sendable
tree snapshots rather than moving a live parser between executors, leaving a
safe handoff for a later background initial parse. The 1 MiB, 14-edit full-parse
capture oracle and mounted public-styler controls pass together with the
pairing tests: six selected tests in two suites on 13 November 2026. This
validates reusable cache state, not the product's large-file path or its
whole-edit latency. The next adapter must still own revision-safe parsing and
painting before the 8,192-unit fallback can change.

The production cache now resolves combined root/injected tokens for a bounded
visible range, retaining the same names and clipped UTF-16 coordinates as the
independent capture oracle. The mounted test feeds these production tokens to
the public styler and compares the resulting rendering attributes after four
edits and viewport moves. The source-length guard rejects a stale cache or
out-of-bounds range before querying. A focused rerun passed all six tests in
two suites after this addition; it still does not exercise an automatic app
adapter or establish a full keystroke budget.

The initial full Markdown parse now has a production helper that can run on a
detached executor and return only a `Sendable` tree snapshot. Both 1 MiB cache
controls use that handoff, while their local-window edits and mounted painting
continue on the main actor. The same six-test selection passes after this
change. An editor owner still has to schedule/cancel the initial task and
reject a result if the document revision or lifetime changed meanwhile.

The final locked optimized package selection passed all six tests in two
suites. Its 14 bounded candidate steps on the 1 MiB corpus took roughly
0.26–0.78 ms each, while the mounted public-styler case passed in 8.906 s.
These timings include the local cache selection/parse/capture in the probe,
not a real editor keypress or settled highlight, so the 50 ms/8 ms whole-path
criteria remain unproved.

## Next qualification

Extend the mounted capture probe across repeated edits and viewport moves.
Compare rendering-attribute runs with a fresh full-parse oracle after each
edit. Include a held stale result, a structural edit,
Unicode/CRLF geometry, IME/undo and teardown negatives. Only then integrate a
production adapter under the size policy and run complete Release/hosted/native
measurements. This probe adds no product UI or user-visible promise by itself.

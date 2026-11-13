# Issue #18: production owner for bounded Markdown color

## Owner summary

The merged section cache can answer visible Markdown token queries after a
small edit, but the app still disables syntax color above 8,192 UTF-16 units.
The next step is one highlighter owner per editor. It must connect real storage
edits and viewport movement to that cache without letting an old background
parse paint a newer document. Unsupported edits remain plain until a fresh
parse completes. The existing reduced-mode policy stays active until an exact
Release app demonstrates the complete typing and painting budget.

## Current boundary

- `EditorView.Coordinator.shouldChangeTextIn` sees the old live storage source
  before AppKit mutates it. Its `preEditObserver` can synchronously select and
  copy a bounded old window. It cannot retain `NSTextStorage.mutableString`.
- `HighlightingStorageGate.didProcessCharacterEditWithGeometry` sees the actual
  new range, delta and length after mutation. It fires before the coordinator
  calls `textDidChange`, so `EditorTextSystem.contentRevision` is too late to
  authorize a parse completion in that interval.
- `MarkdownEditPairing` admits only a proposal whose post-edit geometry and
  replacement bytes match. Programmatic replacement, undo, nested edits and
  composition without an exact proposal must refuse the local cache update.
- `EditorTextSystem.visibleUTF16Range` can return nil when mounted layout
  cannot establish both viewport edges. The cache separately caps a token
  query at 65,536 UTF-16 units.

## Ownership and event order

1. A Markdown-only owner binds to one `EditorTextSystem` and one highlighter
   lifetime. Its private storage generation increments synchronously at every
   actual character-edit callback, before any asynchronous completion can
   inspect editor state. Language/theme changes and teardown invalidate the
   same publication authority.
2. At a pre-edit proposal, select one bounded old-source window through the
   cache and retain only owned bytes, geometry and replacement. At the storage
   callback, compare the proposal with the actual edit. A mismatch discards
   the candidate and schedules an off-main full parse of an immutable source
   snapshot. No TextKit style operation runs inside `processEditing`.
3. A matching edit reads the bounded new window after storage mutation,
   reparses that window, updates the cache only if root-section shape and
   geometry still match, then queries the current mounted viewport. If any
   condition fails, remove affected color and defer a full parse.
4. Each detached parse captures an owner ticket containing the storage
   generation and lifetime. On return to the main actor, compare the ticket
   with current authority, current language and current source length before
   replacing cache or publishing tokens. An invalid ticket is discarded.
5. The public Neon `TextSystemStyler` applies only clipped visible tokens.
   Theme/font changes invalidate its appearance; viewport movement requests
   the new visible range. Selection, marked text, undo and authored attributes
   remain TextKit-owned. Teardown removes observers and styling ownership.

## Qualification before activation

Mounted tests must hold a full-parse result while a real edit, programmatic
reload, theme change or teardown occurs, then prove the old result cannot
paint. The same test family must cover paired word edits, structural fallback,
Unicode/CRLF geometry, IME/undo and viewport moves. Compare every painted
range with a fresh full-parse oracle. Finally measure main-actor edit time,
background parse queue, memory, visible painting and keypress-to-settled-color
in an optimized 1 MiB Release app. The existing fallback is not removed until
those exact-head and native results are reviewed.

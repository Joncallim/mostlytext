# Bounded Markdown undo and redo in the mounted editor

The production viewport editor now admits an undo or redo without a pre-edit
proposal when the current cached section and the post-edit storage prove one
bounded, plain-prose change. This avoids reparsing the entire document for that
case. Ambiguous proposals, structural changes, edits crossing sections and
stale caches retain the full-parse fallback. The authored text and undo manager
are not modified by the highlighter.

## Why this path changed

TextKit's undo and redo reach the storage delegate without the ordinary
pre-edit proposal. Before this change, pairing returned no match and the
session always retired its cache and parsed the full Markdown document. The
historical production-store display receipt on issue #18 recorded undo and
redo at 1,753.210 and 1,958.215 ms respectively. Those values include more
work than the component probe below and are not a direct before/after pair.

The new selection requires the storage length and delta to agree, a bounded
cached section, a callback range containing the inferred changed bytes, exact
UTF-16 equality of the unchanged prefix and suffix, and the existing prose and
paragraph-interior guards. The session only attempts this when its cache was
current before the storage edit and no proposal was seen. A parsed replacement
still has to preserve the cached section shape; otherwise the full parse runs.

## Local evidence

The 1,048,804-byte opt-in Release mounted-session fixture made twelve ordinary
edits, then cleared its test-only undo history and made one isolated word
insertion. It asserted the exact source after the insertion, undo and redo.
The final measurement recorded undo **24.009 ms** and redo **22.791 ms** through
storage, parse settlement and a painter call. Both used bounded unpaired
windows; the session counted 15 local parses and one initial full parse. The
12 ordinary edit settlements ranged from 8.940 to 10.246 ms. This probe does
not measure automatic input-to-visible bitmap paint.

The first Release benchmark attempt failed its new unpaired-count assertion:
it called undo/redo after twelve alternating edits without isolating a text
action. Both observed storage callbacks had zero character delta, so those
calls did not exercise the intended undo/redo edit. The test now clears only
its own history, makes a fresh insertion and asserts the intermediate source
after each action. The failed attempt and its cause are recorded here; it is
not presented as a product failure or erased by the corrected run.

The cache regression compares full-size undo/redo visible tokens with a fresh
full-document parse. Mounted editor tests confirm real TextKit undo/redo takes
the unpaired path and preserves visible-token parity. Structural and
cross-section edits are refused. Edit-pairing tests confirm a failed or nested
proposal cannot be mistaken for an unpaired edit. Ordinary compliance and
changed-file SwiftFormat/SwiftLint pass.

## Remaining acceptance

Issue #18's 50 ms **input-to-visible-paint** target remains unproved and its
previous hosted failures remain failures. The first-edit main-actor scheduling
gap is not addressed by this change. Issue #19's historical triggering offset
and complete lifecycle matrix also remain open. The protected native
checkpoint remains deferred until the owner explicitly resumes it.

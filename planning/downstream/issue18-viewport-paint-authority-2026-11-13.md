# Issue #18: mounted viewport paint authority

## Decision

The future large-Markdown highlighter needs a visible UTF-16 range before it
queries cached section tokens. `EditorTextSystem.visibleUTF16Range` uses the
mounted clip view and TextKit 2 layout fragments at its upper and lower edges.
It returns whole fragment ranges so a caller can invalidate complete
paragraph presentation without copying or searching the 1 MiB document. A
headless layout, missing edge fragment, or inconsistent range returns nil; the
highlighter must keep plain presentation or defer work rather than guess a source range. The caller
still enforces the section cache's 65,536-unit paint limit.

The existing top-visible offset and gutter code established the clip-view to
text-view coordinate conversion. This method reuses that same conversion and
TextKit's document offsets. It does not introduce a second parser or attach
anything to the production highlighter.

## Evidence and limit

On the original dependent `feature/issue18-edit-pairing` source `aff17fbc`, the focused
`EditorScrollAPITests` selection passes all 10 tests in one suite in Debug.
The mounted-window case checks that a deep scroll yields the same UTF-16 start
as the existing top-visible API and a bounded nonempty range; the headless case
requires nil. This slice is now based on main `625ba7fd`, after the cache PR
merged with an identical tested tree. Exact-head hosted testing is still required.

An initial assertion that a requested `scrollToVisible` target must be inside
the clip failed: this older fixture deliberately sets a shorter text-view frame
than its complete text and only promises a deep, in-bounds top line. The final
assertion compares the *actual* mounted viewport, rather than converting that
scroll request into an invented visibility guarantee. This is not a Release
latency measurement, a 1 MiB viewport benchmark, or an automatic styling path.

Next, the highlighter owner must observe viewport movement, pair actual edits,
parse off the main actor when needed, discard stale revisions, and apply cached
tokens through Neon's public styler. The 8,192-unit production fallback stays
active until those paths and the full Release keypress budget pass.

The production owner needs its own monotonic storage-edit generation. The
storage gate's `didProcessCharacterEditWithGeometry` callback runs before
`EditorView.Coordinator.textDidChange` bumps `EditorTextSystem.contentRevision`.
An async parse completed in that interval cannot use the latter value alone
as proof that it still belongs to the live storage. Increment the owner's
generation at the gate callback, bind parse results to it and to the current
highlighter lifetime, and reject stale completion before any style publication.

# #19: line positions during same-length storage edits

The highlighter's line-offset cache used `EditorTextSystem.contentRevision` and
text length as its invalidation key. A same-length edit that moves a newline
changes neither value when Neon's storage delegate runs: `textDidChange`
publishes the editor revision only afterward. Neon can therefore receive a
point from the previous text while processing the new text.

On current `main` `f24f0bb0`, the new controlled package regression primed the
production transformer for `a\nb`, replaced the newline with `x`, and read
offset 2 inside the storage callback immediately before forwarding to Neon.
The storage edit count had advanced, the editor revision had not, and the
transformer returned old point `(row: 1, column: 0)` instead of the new
`(row: 0, column: 4)`. The single expectation failed. The test's initial
hard-coded revision-zero assertion was corrected before this failing run; it
was a fixture assumption, not a product failure.

The first proposed fix invalidated in the gate's `willProcessEditing`. Independent
review found that this was too early: pinned Neon captures the *old* endpoint
in its will callback, then asks for new coordinates in its did callback. That
proposal was not merged.

The corrected highlighter primes its old line table when Neon is attached.
The gate forwards Neon's will callback against that table, then advances a
forwarded-edit generation and primes the new table before Neon's did callback.
This also handles edits that shrink the document: old endpoints are clamped to
the old cached length during will, and new endpoints use the new length during
did. The controlled regression checks both phases for newline removal,
insertion, Unicode and CRLF relocation, plus a shrinking replacement. A
separate edit/fresh-render comparison passes after newline removal and
restoration.

These are local package-component observations. They do not reproduce the
historical SwiftTreeSitter out-of-range read, establish its original
`byteOffset`/`limit`, satisfy the complete #19 lifecycle matrix, or close #18's
50 ms input-to-paint target. The protected native checkpoint remains deferred.

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

The mounted highlighter now includes the storage gate's pre-Neon character-edit
count in the transformer's generation. This invalidates the line table before
Neon asks for post-edit points. The controlled regression passes for newline
removal, insertion, Unicode and CRLF relocation. A separate edit/fresh-render
comparison passes after newline removal and restoration.

These are local package-component observations. They do not reproduce the
historical SwiftTreeSitter out-of-range read, establish its original
`byteOffset`/`limit`, satisfy the complete #19 lifecycle matrix, or close #18's
50 ms input-to-paint target. The protected native checkpoint remains deferred.

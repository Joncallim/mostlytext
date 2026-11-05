# Scalar-safe native Preview transport qualification

The Foundation-only input rewrites exact original UTF-16 ranges without splitting
surrogates or CRLF, proves UTF-8 expected bytes, rejects duplicate identities and
all overlapping source edits, checks literal marker-family collisions and budgets
the COMPLETE expanded input before materializing. Definitions and ordinary shared
reference repairs participate in generated coordinates. The exact three-file
Foundation fixture passes 9 tests /one suite in Debug and Release (0.003 s each).
No native/product/font/drawing code executes in that fixture. `foundation-files.json`
and the manifest reproduce it from this checkout using a fresh output directory.

The actual Preview parser/restore uses Textual with source positions and no secondary
math extensions. It restores through actual Unicode-scalar indices, preserving
inherited attributes and own opaque occurrence identity. Missing renderer output
retains authored source. Invalid source or missing/duplicate/unknown/entity-forged/
code/HTML markers recover the whole authored visible block without partial output.
Public app navigation still must validate the current snapshot before using an ID.

Actual PreviewTests compile, including seven native-parser regression functions
and an owned-host geometry test for all six Unicode adjacency cases. The minimal
fixture copies ten exact app source/test/support files as a module named Preview
with the SAME three immutable app pins; compile/link succeeds without executing it.
Its receipt and manifests are retained. The first source lint found an oversized
initializer/complexity; admission, projection and materialization were moved to
named helpers, leaving assertions and policy unchanged. Both first failure and
subsequent full strict lint/pinned-format passes (1,399 files) are retained.
Five explicitly synthetic verifier/source-tamper controls pass; the synthetic log
was deleted and is not native evidence.

**Hosted execution of this extended transport fixture is pending.** The separate
four-test native placement/font correction already passes on Textual c52cb583;
its baseline failure and qualified run are in the sibling native-math-policy packet.
No production Preview/Export grammar switch, final app/VoiceOver/RC acceptance or
whole issue closure is claimed by this unit.

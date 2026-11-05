# Scalar-safe native Preview transport qualification

The Foundation-only input rewrites exact original UTF-16 ranges without splitting
surrogates or CRLF, proves UTF-8 expected bytes, rejects duplicate identities and
all overlapping source edits, checks literal marker-family collisions and budgets
the COMPLETE expanded input before materializing. Definitions and ordinary shared
reference repairs participate in generated coordinates. The exact five-file
Foundation fixture passes 12 tests /two suites in Debug and Release (0.004 s each).
No native/product/font/drawing code executes in that fixture. `foundation-files.json`
and the manifest reproduce it from this checkout using a fresh output directory.

The actual Preview parser/restore uses Textual with source positions and no secondary
math extensions. It restores through actual Unicode-scalar indices, preserving
inherited attributes and own opaque occurrence identity. Missing renderer output
retains authored source. Invalid source or missing/duplicate/unknown/entity-forged/
code/HTML markers recover the whole authored visible block without partial output.
Public app navigation still must validate the current snapshot before using an ID.

Actual PreviewTests compile, including eight native-parser regression functions
and an owned-host geometry test for all six Unicode adjacency cases. The minimal
fixture copies twelve exact app source/test/support files as a module named Preview
with the SAME three immutable app pins; compile/link succeeds without executing it.
Its receipt and manifests are retained. The first source lint found an oversized
initializer/complexity; admission, projection and materialization were moved to
named helpers, leaving assertions and policy unchanged. Both first failure and
subsequent full strict lint/pinned-format passes (1,399 files) are retained.
Five explicitly synthetic verifier/source-tamper controls pass; the synthetic log
was deleted and is not native evidence.

**First extended hosted run 42067095010 FAILED.** All six scalar attributes and
own native frames, reference target/key cases, missing-renderer styling and entity
forgeries pass. Two assertions incorrectly assumed that ordinary content BETWEEN
inline HTML tags is excluded from math. The retained real shared-parser probe proves
only the tags are literal; the revised case requires preserved literal tag text and
the native attachment in eligible content. Code/fence/hidden-definition exclusions
remain unchanged. This reconciles the adapter with the existing source policy.

The run then traps on the original foreign-source-position regression:
Range(position, in:) reuses cached offsets from a different string. The correction
never invokes that convenience initializer: a bounded exact-input map validates
public 1-based UTF-8 line/columns and scalar endpoints before converting to UTF-16.
LF/CRLF/CR, multibyte final scalars, interior bytes, empty/reversed/out-of-range and
Int.max positions have Foundation-only coverage. The native crash regression stays
unchanged. Full failure log and exact before parser/tests are retained. Numeric
position conventions are documented by Apple at
https://developer.apple.com/documentation/foundation/attributescopes/foundationattributes/markdownsourceposition.

**Corrected extended hosted execution remains pending** (25 tests/seven suites). The separate
four-test native placement/font correction already passes on Textual c52cb583;
its baseline failure and qualified run are in the sibling native-math-policy packet.
No production Preview/Export grammar switch, final app/VoiceOver/RC acceptance or
whole issue closure is claimed by this unit.

The first numeric-map hosted run 42068181327 safely rejects the unchanged foreign
position regression (no crash), but reports 13 assertions because end columns at
the inclusive final UTF-8 byte of a non-ASCII scalar are rejected. The complete
raw run and exact before-map source are retained. The corrected map accepts the
first or inclusive final byte as a scalar end while still requiring a first-byte
start and rejecting nonterminal interior bytes, invalid ordering and out-of-bounds
values. Existing invalid-position controls stay unchanged; inclusive end/invalid
start controls are added. Native tests record actual numeric parser positions
and rewritten byte counts. This corrected head still needs actual hosted results.

## Qualified actual extended result

Hosted run 42069019008 on exact PR91 head ef26e5c9f37b437a625edebdefef1b28271ac2f0
PASSES all 25 tests/seven suites in 1.332 s, with exact source/pin/result verification.
The unchanged foreign cached-index crash regression, malformed-position controls,
all six Unicode/source/attachment cases and all six distinct own native frames pass.
Actual numeric source-position records confirm inclusive final UTF-8 columns for
the non-ASCII neighbors. This raw result is retained in the dependent activation
branch so the already qualifying parent head need not move for evidence packaging.
Complete parent CI and final product/native acceptance remain separate gates.

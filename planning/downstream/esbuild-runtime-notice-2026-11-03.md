# Preserve the generated parser runtime attribution

Baseline main 0f4348d6. The 3,980 outer parser positions without inner source
association include an emitted esbuild helper preamble, not only unknown package
code. Add Evan Wallace's complete MIT text as a conservative runtime attribution,
using two complete helper bodies that token-match an immutable licensed esbuild
reference. The emitting esbuild version is not established and must remain visibly
unresolved; no exact npm identity or full parser-audit closure may be inferred.

Pin the shipped bundle, official map, exact parser chunk, upstream runtime source
and license. Read captured packages only as data. Verify full helper bodies after
only reviewed whitespace/statement-semicolon/export-prefix normalization; reject
strings/regex in that narrow comparison rather than pretending to be a general JS
parser. Count actual outer source references on helper body probe lines and the
runtime preamble, with all coordinates one-based in the report. Preserve the
original 3,980-position report; record the bounded new classification separately.

Change only compliance evidence/tool/tests, one attribution record/text and
regenerated notices/SBOM plus current docs. No Swift/runtime/renderer/pin/guard or
release-policy changes. Positive real-input replay, semantic-change and malformed
selection controls, complete compliance suite, unchanged notice-reader bound,
compile-only artifact checks and hosted Compliance precede merge. All six strict
release failures remain; other unassociated positions and embedded origin questions
are not silently cleared. No application/native execution or publication.

Integration reconciliation: main 68b72f76 brings the Help-menu correction, whose
complete hosted app/package CI passed at 0c1625a0. Its existing localized action
and current documentation are retained. Against this integrated baseline this
notice unit changes no Swift source, renderer, lock, guard or release policy.

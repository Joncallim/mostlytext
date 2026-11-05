# Requery complete old captures before replacing injection ownership

## Owner outcome and baseline

Replacing a character with a newline must not silently remove highlighting from
the remaining paragraph. A new deterministic valid-scalar edit corpus reproduces
that loss at edit44: the root tree equals a fresh parse, but the inline range
524..<582 is missing. A full query restores it. This is an injection-ownership
coverage defect, separate from native painting and the lexer performance patch.

Application baseline4b162baefac56256cb335afcf684544be4dbc0dc (pending PR #79),
with PR #78/#79 source stable and main9b2cd216 at intake. Dependency baseline
SwiftTreeSitter1b1c85e94df6421a0e4bdcb9f3afaddb16b75d43, Neonbaf93c72924e31e16b84adced6ee29cb02934c3b,
runtime0.25.10. Both predecessor PRs require exact-head CI and integration first.
Existing range reconciliation already expands queries over returned fresh
capture extents. It does not expand a partially queried old capture before
retiring it, so a replacement starting just outside the initial window is lost.

## Contract, ownership and interfaces

Keep all public APIs, grammar bytes, threading and parser reuse behavior intact.
LanguageLayer owns the correction: before treating an old capture as replaced,
query its complete current extent. Extend the existing monotonically growing
coverage closure with nonempty old ranges that intersect it, alongside complete
fresh capture extents. Requery until neither old nor fresh ranges expand the
coverage. Only then reconcile languages. Preserve unrelated unqueried captures,
vanished-language retirement, removed-span invalidation and restricted-empty
layer retirement. Do not use an unconditional whole-document query or a boundary
heuristic as an undocumented substitute.

The closure uses the same current-coordinate included ranges as reconciliation,
with finite endpoints and no new allocations proportional to document characters.
There is no new filesystem/network capability, actor, mutable global or policy.
Malformed range generation must remain visible; this patch does not change the
runtime setter, parser thresholds, source text or large-document fallback.

## Verification and execution

1. Retain exact old-source failure and diagnostic: root AST equality, missing
   child range, unequal captures and restoration after explicit full resolution.
   Minimize a boundary-movement fixture independently of the long random corpus.
2. Apply the private coverage-closure correction only. Run the deterministic
   actual Markdown root/inline scalar corpus, all prior range regressions and
   upstream suites Debug/Release in inspected Foundation/C fixtures. Include
   ordinary partial windows, cross-language nesting, moved starts, vanished and
   empty layers. Never weaken fresh-query equality or hide a failing case.
3. Publish an immutable owner SwiftTreeSitter child and manifest-only Neon child,
   retaining the client, semantic-paint and buffer fixes. Pin app/vendor manifests
   consistently; only those two application pins may change. Preserve licences
   and update inventory/notices/SBOM. Compile locally, execute full hosted CI,
   review exact head and merge after predecessors. Update owning issues and
   immediately audit all open contracts after every actual issue mutation.

## Residual limits and stop conditions

Do not claim whole-editor latency, native acceptance or a fixed C runtime from
this unit. The independent C lexer optimization remains unadopted. Its raw-range
corpus also finds an original-runtime incremental/fresh discrepancy, including
valid UTF-16 edits; retain it separately until its input/domain implications are
understood. This unit must prove its own actual-root capture failure fixed.
If capture parity requires parser-policy changes, unconditional full queries,
new public APIs or test/deadline weakening, stop this slice for a focused design
revision. All native execution and release/rights/publication gates remain.

## Focused revision: explicit fresh parsing for Markdown inline

The old-capture coverage correction advances the same actual-root corpus from
failure44 to failure1745. At1745 the root AST and child included ranges both
match fresh; only the inline child AST differs. Explicit whole resolution does
not repair it. This independently matches the retained original-runtime UTF-16
incremental/fresh discrepancy. Do not weaken the 2,000-edit oracle or confuse
these two causes.

Add one source-compatible public configuration value,
LanguageConfiguration.reusesPreviousTree, default true. Existing initializer
signatures and other languages keep their behavior. LanguageLayer consults it:
when false, reset the parser and parse without an old tree, retaining the old
state only for changed-range comparison. Included ranges, queries, cancellation,
thread confinement and ownership reconciliation remain intact. The app selects
false only for MarkdownInline in its existing grammar factory. This is a focused
revision to the prior public-API stop rule, justified by the reproduced parser
state discrepancy; it adds no user setting or new dependency direction.

Keep a minimal moved-capture test on the default policy to verify the coverage
fix independently. The long actual-root corpus uses the same explicit inline
policy as production and must pass unchanged fresh-capture equality. Retain both
negative results and source/input hashes. Measure Release component edit costs
at eligible sizes before adoption; keep the8192-unit fallback and whole-editor
performance gate. The lexer optimization remains separate and unadopted.

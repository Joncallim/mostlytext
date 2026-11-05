# Repair inline highlighting range replacement

## Owner outcome and baseline

Edits containing Markdown inline syntax must leave the same highlighting as a
fresh parse of the resulting text. This first dependency correction prevents
rejected included-range lists from retaining stale inline parse state. It does
not lift the size fallback or establish the 50 ms whole-editor budget.

Application baseline: main5c867c5cecb1121ea157d4b6df25340f4ab14f86. Inspect
AGENTS.md, EPIC_STANDARD.md, RELEASE_HARDENING.md, h5-dependency-followup.md and
the H5 dependency/profile/Neon evidence. Current pins: SwiftTreeSitter
cbe31cb3601aa29c1f64b6e4328733511126d6d5, tree-sitter0.25.10 at
da6fe9beb4f7f67beb75914ca8e0d48ae48d6406, Neon dabf50c947148c49acd0d321dfe8f3805d10b3da.
The vendor Markdown scanner already contains the safety backport; do not replace
it with the old benchmark scanner. The owner has approved narrowly targeted
patches/forks as part of the full remaining-issue plan.

## Reconciliation and readiness

H5 problem B is not hypothetical: retained layer-only tests reproduce stale
collapsed/overlapping included ranges; the C parser rejects the replacement.
The historical B1 experiment uses an old-times-new filter and never qualified
in this application. Existing Neon replacement tests have two known-issue
wrappers plus a Release-only experimental widened-edit case. They are not
removed merely because a layer-only test passes. Current Neon and app already
contain later geometry/lifecycle work; requalify the current exact pins.

H5 A (linear lexer included-range search), inline GLR/reuse, main-thread style
application, Neon's sublayer invalidation and invalidation-buffer drift remain
separate concerns. None is inferred repaired by this unit. The review packet's
outward-facing upstream contributions are not authorized by the owner-fork
strategy; prepare them locally without sending messages or opening upstream PRs.

## Ownership, interfaces and range policy

Patch an owned exact-base SwiftTreeSitter fork, confined initially to
LanguageLayer.encorporateRanges and its pure range merge. Keep the existing
public API and tree-sitter grammar/runtime revisions unchanged. Fresh nonempty
ranges are authoritative over any overlapping old range, including a different
start offset; discard old collapsed ranges. Preserve disjoint and adjacent
ranges exactly, including their original points. Sort by byte coordinates.
Use sorted lists and a sweep, avoiding the historical O(old*new) filter.
Invalidate removed old spans as well as newly admitted spans so stale styling
can be cleared. Preserve the meaning of an empty restricted layer: never pass
an empty range list that would silently select the entire source document.

No app/Workspace dependency, new network path, source normalization, geometry
recomputation or threading change. Calls remain on the existing layer owner.
Invalid newly generated overlapping inputs must not be treated as valid proof;
if observed, retain the failure and resolve that distinct admission defect.
Parser's failable included-range API is a separate subsequent unit; this first
fix does not silently replace its public setter with a trapping API.

## Execution and failure boundaries

1. Reproduce the existing eight Foundation/C-only layer scenarios against the
   exact pins; retain stock and historical experimental output separately.
2. Write strict new layer regressions: shifted-start overlap, collapsed ranges,
   replace/delete/type/delete-one-turn, retained neighbors, Unicode and line
   endings; compare range lists, tree structure and captures to a fresh parse.
3. Apply the minimal sweep correction and run complete upstream library tests
   plus Debug/Release Markdown layer regressions. Local checks import only
   Foundation and C parser/library modules, never AppKit/SwiftUI/WebKit.
4. Publish a pinned owner fork after source/tests review. Update application
   manifest/lock, inventory/provenance and full patch evidence together. No
   unrelated dependency changes. Resolve in an owned checkout and verify pins.
5. Run full hosted application qualification. Strengthen only actually repaired
   Neon expectations; leave any remaining failures and native gates visible.
6. Review, merge exact head, verify actual merge tree and update #6/#18/#19/#17
   evidence only where supported. Reaudit all open issues after each update.

The native EXECUTION_HOLD remains. Existing large-file fallback, renderer
limits, all original performance ceilings, known original failed runs and six
strict attribution/source failures remain. Do not close the full issues from
this component pass. Whole-app/native editor, IME, scroll and current-line
geometry acceptance are separate evidence.

## Reproduced refinement before adoption

The new combined-edit regression proves a second omission in the historical
B1 sketch: after typing and deleting across injections, the ROOT tree equals a
fresh parse, but a formerly valid inline range can survive without overlapping
any new injection. Merely filtering collapsed/overlapping captures is therefore
insufficient. Keep the actual failing output; do not remove this test.

Resolve must treat the requested source set plus returned complete injection
capture extents as authoritative coverage. Retire old captures intersecting
that coverage even if no replacement exists. Reconcile existing languages as
well as newly returned languages, so disappearance of a language is handled.
Keep unqueried neighbors unchanged. Once a restricted layer has no remaining
ranges, retire that sublayer rather than setting an empty C range list (which
would select the whole document). This changes only existing private layer
reconciliation; no new public API or document behavior is introduced. Test
partial coverage/neighbor retention, vanished injections, point/range identity
and a fresh-root control in addition to original regression shapes.

## Final review: complete expanded query coverage

A new deterministic cross-language regression proves that expanding replacement
coverage without requerying loses unqueried narrow captures inside another
language's wide capture. The initial full hosted pass does not cover this case.
Before integration, repeat the shallow injection query over its monotonically
expanded capture coverage until that coverage is unchanged, then reconcile all
languages against that complete result. This preserves legitimate nested/overlap
captures while still retiring a changed language whose tag lies outside its
body. The fixed point is bounded by the finite immutable root tree's capture
extents. No authored content is read outside the already admitted root snapshot.
Retain the failed first-head regression and qualify the corrected fork/app head.

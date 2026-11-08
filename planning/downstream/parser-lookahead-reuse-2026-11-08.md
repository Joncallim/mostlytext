# Check included-range lookahead before reusing Markdown tokens

## Owner summary and ready baseline

Editing inline Markdown must produce the same syntax highlighting as reopening
that exact source. Investigate a narrow upstream correctness fix missing from
the pinned C runtime: an old scanner token can depend on characters just beyond
its own text, so widening a parsing range must invalidate that dependency too.
This is separate from the whole-document 50 ms requirement and the original
Debug abort; no claim about either follows from this work.

Baseline main is `a46c57c4b62376b67492cf67421a4961fdf55c1c`. PR146's independent
inline styling candidate `024103b3` remains frozen with seventeen first workflows
in progress. This branch must not merge or change that candidate while its firsts
are incomplete. Read AGENTS.md, EPIC_STANDARD.md and RELEASE_HARDENING.md; preserve
all accepted source, identity, geometry, scanner-safety and shared-runtime work.

## Existing source and primary evidence

The active runtime is `3b1fb00f8c4f8907073f9b7342a807a0231867fa`. Its
`ts_parser__reuse_node` tests included-range differences against only the token's
own end byte. The maintained scanner backport and current wrapper range-replacement
repairs solve different defects. Confirm exact live pins and wrapper behavior
before claiming application reachability; component reproduction is not an
observed native editor failure.

Upstream [issue5636](https://github.com/tree-sitter/tree-sitter/issues/5636) reports
incremental/fresh Markdown-inline disagreement. The reviewed
[fix5641](https://github.com/tree-sitter/tree-sitter/pull/5641), merged as
`15ddfb21edb11831e34d666110b8efe3aa081f9b`, includes a token's lookahead extent in
that range check, preserving the existing EOF sentinel. It was also backported
to release-0.26 in [5656](https://github.com/tree-sitter/tree-sitter/pull/5656).
Do not upgrade the runtime or grammar wholesale or relax fragile-node safety.

## Named pre-implementation question

Does the exact current C runtime reproduce stale code-span structure with the
actual vendored Markdown-inline grammar when an included range expands, and does
only the exact upstream guard correct it? Require failing-before evidence before
shipping any patch. Keep unchanged-range, shrink, prefix/position, UTF-8 and
UTF-16 little-endian controls, and compare incremental trees with fresh trees.
If the actual grammar does not reproduce, retain the result and stop adoption;
do not manufacture a different application failure or infer a performance fix.

## Ownership and interfaces

Use the existing runtime public C API and current vendored grammar in a standalone
console driver. It owns generated fixture bytes and parser/tree lifetimes only.
The existing parser API/ABI, wrapper interfaces, edit geometry, source bytes,
range policy, query capture names, public modules and application behavior remain
unchanged. No new package or dependency is introduced by the probe.

## Invariants, data flow and failure handling

For each fixed fixture, parse the narrow included range; retain the old tree;
expand or shrink to the intended range, reparse incrementally, and compare to a
fresh parser over the exact same input/ranges/encoding. Capture the full ordered
node symbol/named/error/missing/extra/byte/point/depth facts, not a timing badge.
UTF-16 byte offsets and columns use two bytes per code unit. Keep all trees live
until comparison, check every allocation/API result and free every owned value.
The first driver records differences without pretending they pass. A shipping
regression must require equality after the guard correction. No assertion,
fixture byte, deadline or resource policy changes to turn a failure green.

## Trust, execution and resource budgets

Local execution is limited to an inspected pure-C console linked only to normal
system C libraries. Inspect actual linkage before running; no AppKit, SwiftUI,
WebKit, CoreText, graphics, JSC, Node, WebAssembly or product runtime. Read only
reviewed pinned source and generated small fixtures; no owner documents, account
preferences, GUI, entitlement, signing or release activity. Compile commands,
all source hashes, actual binary hash/linkage, full stdout/stderr and bounded
process outcome are retained. Start with tiny fixed cases and a 10-second
external process bound. Sanitizers remain required; a timeout or crash is failure.

No performance claim follows. The original 50/400/500 ms gates and 8,192-unit
large-document fallback remain. This correctness fix may deliberately reparse
more text when the old cache is invalid. Accessibility, localization and durable
formats have no new UI/string/encoding policy; existing native checks remain.

## Adoption boundaries and slices

1. Commit this architecture before code. Validate current immutable source and
   inspect standalone linkage. Retain original exact C reproduction/control data.
2. Only if reproduced, compare a source copy with the exact upstream guard change;
   preserve EOF and every other runtime byte. Require all fixed cases and actual
   grammar/query/ownership/sanitizer controls, including existing C comparisons.
3. Before dependency publication, record the precise selected source delta,
   provenance/license preservation and coherent runtime/wrapper/Neon/vendored
   manifest update architecture. Current PR146 must qualify/merge before this
   branch changes main. Resolve an exact new graph through the authorized hosted
   path, preserving unrelated revisions including the qualified inline fix.
4. Qualify complete app/package, real wrapper/native editor/theme, original
   geometry/fresh-parse regressions and exact integration identity before merge.
   Update canonical owning issues only for proved scoped behavior.

## Stop conditions and definition of done

Stop for missing reproduction, changed semantics/ABI/ownership, unexpected input,
source drift, new warnings, native failure or a need to weaken existing controls.
Do not discard first outcomes or retry unchanged functional failures. Record
ordinary local choices in this architecture rather than silently expand it.
The probe alone is not production completion, native acceptance, performance
repair, independent rights approval or release readiness. Broad issues stay open
until their separate original criteria are fulfilled.

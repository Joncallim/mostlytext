# Qualify parser improvements independently of Preview activation

## Owner summary

Bring the reviewed parser build improvement and strict editor replay controls to
current main without activating the blocked Preview resource consumers. The
parser uses the same C implementation through its existing combined input;
existing editor controls exercise real background parsing during replacement.
This can reduce parser overhead and retain a useful regression boundary, but it
does not establish the original Debug abort cause or the full product latency
budget. Old failing results remain failures. Integrate only after fresh complete
qualification, and retain any new failure before revising the approach.

## Live baseline and reconciliation

Start at actual main c321e9735c091cb3871240ac1036f98085eb1858. PR113 has now
independently integrated PR107 publication ownership and direct test-window
ownership. PR106 source15b2306c and PR101 sourcec3a1516b remain unmerged; their
old Release ceilings failed, so their old checks cannot authorize integration.
PR108 source0557 includes these sources but failed two Preview Debug pairs.
Do not merge that candidate, Preview PR100, its resource routing or diagnostic
observer changes through this unit. No existing failure is relabelled.

Preserve both reviewed heads as actual merge parents. Resolve only documentary
checkpoint collisions and additive control-count/required-control reconciliation.
Product and dependency blobs must equal the reviewed inputs except disjoint
changes already on main. Compare the complete resulting source graph with the
expected three-way merges. Keep all original licences, provenance and failure
packets. The three immutable parser pins and notices travel together; the other
21 pins and the Textual publication repair remain unchanged.

## Ownership, interfaces and state flow

Tree-sitter runtime3b1fb00f8c4f8907073f9b7342a807a0231867fa changes only the
package source list and patch notes from its reviewed parent. The effective
13 C inputs, defines, headers, 260 external symbol names and implementation
bytes stay exact. SwiftTreeSitter76f93e7e325dcd05561a13ed63bcc92cb85be8da and
Neon6074d1a50c7076b2e59d8d0619554b542e096afa are manifest-only children.
No new dependency direction, parser algorithm, grammar/query, memory policy,
public API, concurrency, cancellation or source lifetime change is permitted.

The nil-by-default internal GrammarRegistry observer remains a testing control.
Only opted-in hosted fixtures hold one actual background injected-language
request, then shrink/grow the real mounted editor and compare nonempty fresh
highlighting and exact native/model source bytes. It cannot hold the main actor
or the cache lock. Ordinary production callers continue to supply nil.

## Trust, accessibility and interoperability

All document processing stays local/offline. No preferences, recovery, journal,
resource grant, command endpoint, signing, release or publication control changes.
Owner native execution remains held. Hosted fixtures use generated source and
identity-owned bounded processes, never the owner account. Existing exact-byte,
CRLF, emoji, alias, retained-snapshot and independent-cursor controls remain.
No user strings or accessibility semantics change; native theme bitmap controls
and real math/heading integration must still qualify the changed dependency graph.

## Ordered implementation slices

1. Preserve reviewed PR106 and PR101 heads as parents, review each conflict,
   reconcile only the exact complete theme inventory and required semantic
   controls, verify all product/pin/notices deltas and run pure preparation,
   compliance, inventory, strict format/lint and diff checks.
2. On the immutable combined head run full normal CI (complete package/app
   selections, all four app/public mostlytext builds, app/UI compilation), both
   complete theme selections including identical baseline failures, actual
   orientation mutation and restoration, both strict highlighting replays,
   complete shared-subtree C semantic/work/sanitizer stages, both real app
   math/heading selections and standalone native math controls.
3. Independently bind every required artifact to the actual source/synthetic
   tree, complete input and fixture keysets, pins, binaries and owned statuses.
   Review actual fresh head and threads. Merge only if every required gate is
   complete and green, source/computed/synthetic trees agree, then verify actual
   parents/tree and canonical clean fast-forward. Update owning issues with
   bounded completed units and reevaluate the whole backlog after each update.

## Performance and failure rules

Keep 500ms full-highlight, 400ms direct-parser and original 50ms product budgets,
original fixtures, selections and all compile/execution limits unchanged. The
expected complete theme selection is main's1085/143 plus shared-subtree and
mounted-replay additions:1087 functions/145 suites, subject to independent
source enumeration. This is an exact completeness check, not a new threshold.
A fresh-head failure stops integration; retain it and diagnose a materially
identified cause rather than rerunning unchanged or accepting a partial pass.
An absent original assertion proves no numeric trigger or failing-before fix.
No green component result closes owner/native/signing/exact-candidate gates.

## Completion and explicit limits

Done is the exact reviewed source integrated after all required fresh checks,
with notices/pins aligned, original failures preserved and issue bodies updated
without weakening their original criteria. Source progress is not whole-issue
closure. Full app responsiveness, original Debug assertion causality, Preview
activation, protected native journeys, independent rights/source approval and
final signed-candidate acceptance remain governed by their owning contracts.

# Investigate repeated capture-sort geometry work

## Owner summary and current evidence

Keep the original highlighting order while avoiding repeated computation of the
same immutable capture positions. This is a named component investigation and
possible narrow continuation of #18/#17, not permission to change test budgets.
Actual main is d607098bdb5046c02d81137b497e0ffe1aa01748. The current PR106
candidate4d7adc90 passes C semantics/work/sanitizers, but its complete Release
selection fails exactly fullHighlight1MB at503.522292ms against500ms, with
394.315375ms parse and109.204ms query. Retain that full result; no unchanged retry
or assumption about its exact cause. Source inspection shows highlights() sorts
QueryCapture values using repeatedly computed node ranges, then creates every
NamedRange. Capture ordering depends on depth, start offset, name component
count and pattern index; tie ordering and empty-name behavior must stay exact.

## Narrow question before adoption

First profile a normal standalone Foundation console using actual8a7e2100
SwiftTreeSitter sources, cd96b385 runtime and exact vendored Markdown C/query
bytes, with the unchanged1,000,008-byte workload. Compare reference and candidate
complete ordered results for ordinary/Unicode/CRLF/CR, nested overlapping and
equal-key captures, empty/multipart capture names, pattern precedence, directives,
query re-execution/current source, ranges/depths and independent concurrent
cursors. A separate representative inline-dense workload must not be replaced
by a convenient synthetic input. Profile first; do not adopt a change without
a demonstrated work/cost improvement and identical public results. Any counter
observation belongs only to disposable source copies, with exact recorded delta.

## Conditional implementation boundary

If supported by the investigation, materialize immutable sort keys once per
capture during highlights(), then sort using the exact existing precedence and
produce the same ordered NamedRange values. Keep public QueryCapture ordering,
node lifetime, predicate/directive evaluation, metadata, match/capture APIs,
threading, query/grammar/runtime bytes and stable equivalent-key ordering. Do
not skip any capture based on assumed query ordering, bypass sorting, change
resolver behavior or attach source/range caches to a shared Query. No counters
or profile drivers enter the shipped library. The .locals()/.injections() paths
stay untouched unless separately proved necessary.

Use a new immutable descendant owner SwiftTreeSitter branch from8a7e2100, then
a manifest-only Neon child fromf97aca5b, preserving all prior runtime/query and
model correctness repairs. Runtime stays cd96b385; only the two coherent wrapper
pins may change. Update app/vendored manifests, exact allowlists, provenance,
notices/SBOM together after component proof. Preserve original licences and all
unrelated objects. No upstream communication, native owner-account execution,
source offer, release publication, fallback8192 or assertion/threshold changes.

## Qualification and completion

Add a canonical actual-library ordering regression. Existing query/global/named
directive, current-tree and concurrent-cursor positives remain mandatory. Run
applicable complete owner-library tests and identical standalone results before
and after; original failures remain inspectable. Compile-only local native work
is allowed, with all native execution hosted on macOS26. Incorporate actual main,
run complete package/app and required Debug/Release native/semantic/mutation
checks on the final coherent graph, independently verify receipts and source/
computed/synthetic trees, and merge only after every required gate passes.
Neither component timings nor source correctness waive the failed500ms guard,
the400ms parse guard, the50ms product criterion, original assertion diagnosis or
owner/signed-artifact acceptance. If a different algorithm or contract is needed,
amend this architecture before changing production code.

## First investigation result: do not adopt the sorting shortcut

An inspected normal Foundation console executes the exact1,000,008-byte workload
with all23,256 ordered results, real metadata, current-range/alias and64 independent
cursor controls. The original five measurements have median query53.216541ms;
a disposable decorate/sort implementation has53.760625ms. Its entire encoded
ordered result matches, but no useful speed improvement is established. A bounded
one-second sample of the original40-iteration normal console attributes152 of
160 match-consumption samples to actual C query traversal, and only6 samples to
Swift sorting. These are one local profile, not product benchmarks or proof of
a final budget. Preserve both raw records and reject adoption: no owner fork,
production query source, pin, native selection or threshold changes.

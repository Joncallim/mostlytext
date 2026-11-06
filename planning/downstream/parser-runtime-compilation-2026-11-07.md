# Profile the parser runtime's combined compilation input

## Owner summary and live baseline

The previous sorting experiment gave no useful gain and is not adopted.
Investigate whether compiling the same parser sources through their existing
combined lib.c input reduces avoidable function-call/optimization overhead.
This is a build-input experiment, with no parser algorithm, query, grammar,
source-lifetime, public interface or test-budget change. Actual main remains
d607098b; PR1064d7adc90 has the retained503.522292ms full-highlight failure.
Its current locked runtimecd96b385's Swift package compiles src files separately
and explicitly excludes src/lib.c; that existing file includes the same runtime
implementation sources. The local C semantic controls already compile this
combined entry point. Do not infer that they qualify the actual Swift package.

## Question and scope before adoption

Compare the actual current separate-file package and its existing combined entry
point using byte-identical cd96b385 C sources/headers/defines, current8a7e2100
Swift wrapper sources and actual vendored Markdown grammar/query/workload. First
verify every C input currently compiled is represented exactly once by lib.c,
with no omitted wasm/platform/runtime implementation. Preserve the original
C11/feature/visibility/platform settings, original licenses and all source bytes.
Only the Package.swift target source/exclusion list may differ. Compare complete
ordered query/tree output, public exported symbol names, actual compiler/linker
inputs and standalone timings. Local source-copy/graph setup must be explicit,
not passed off as the complete application's dependency resolution.

Do not adopt without a measurable component improvement and identical behavior.
An accepted change receives its own immutable owner runtime child fromcd96b385,
then manifest-only SwiftTreeSitter and Neon children. All three coherent pins,
provenance, notices, SBOM and exact reviewed-pair controls are updated together.
All unrelated source objects, license texts, public headers, exported API/ABI,
prior correctness repairs and fallback8192 remain exact. Do not combine the
rejected sorting source or invent new compiler flags, skipped assertions,
threading, memory/timeout policy or upstream contact.

## Required evidence and completion

Inspect normal console linkage before bounded local execution. Retain original
and candidate source inventories, actual build commands/inputs, binary hashes,
separate stdout/stderr/status and complete results. Run applicable documented
parser corpus/query/ownership/sanitizer controls and actual wrapper regressions;
explain when those controls already use the combined entry point and therefore
do not alone prove the package-build delta. Require full fresh app/package and
Debug/Release native editor/theme/mutation/integration checks on the final locked
graph, source/computed/synthetic tree agreement, and normal final review before
merging. No unchanged retry or threshold/fixture change waives the original
500ms highlight,400ms parse,50ms product or historical Debug-trigger gates.
If effective C sources/defines/API differ or the improvement is not established,
retain the result and stop adoption; amend before a different material approach.

## Complete C input reconciliation before the experiment

The current source directory has13 individual implementation C files, excluding
lib.c itself. The combined input includes12 exactly once. The additional
src/wasm/stdlib.c is a separate conditional implementation and must remain an
explicit separate source even though TREE_SITTER_FEATURE_WASM is not enabled by
the current package. The candidate source list is therefore exactly
["src/lib.c", "src/wasm/stdlib.c"], with only lib.c removed from exclusions.
No C file, macro, wasm configuration, header or implementation is omitted or
rewritten. Compare the complete effective original13-file set to the twelve
includes plus the retained stdlib file before accepting this build experiment.

## Adopted component result, pending actual native qualification

The exact original and combined package builds preserve all23,256 ordered
highlights, metadata/current-range/alias/independent-cursor positives and all260
defined external C symbol names. Actual compiler/linker records retain the same
C11/feature/optimization flags and complete13-file implementation set. Five-run
medians are232.540125ms versus210.33625ms; the declared paired confirmation gives
240.56825ms versus213.219417ms. Retain the initial object-path readback and copied
file-mode setup failures; neither is a failed product assertion or native retry.

Immutable runtime3b1fb00f8c4f8907073f9b7342a807a0231867fa changes only Package.swift
and patch notes fromcd96b385, keeping487 other Git objects exact. Manifest-only
SwiftTreeSitter76f93e7e325dcd05561a13ed63bcc92cb85be8da and Neon
6074d1a50c7076b2e59d8d0619554b542e096afa retain102/81 other objects respectively.
Only these three pins change; the other21 owners/revisions and original licences
remain exact. The C qualifier permits only the original subtree.c repair plus
the exact two-line Package.swift source-list change, verifies all13 effective C
source hashes and retains the separate conditional stdlib file. Its5 complete
C semantic/work/sanitizer phases pass again, with1,590 current application input
hashes/24pins and actual local executable digests independently verified. This
qualifies the unchanged C semantics, not the separate package-build delta alone.

The actual optimized HighlightingTests target compiles through the new resolved
graph and lib.c input; all330 compliance tests, inventory, strict lint/pinned
format,6 model pin controls and4 C-authority controls pass. No owner-native
execution occurs. Complete evidence and the preceding503.522292ms failure are
retained in planning/downstream/evidence/parser-runtime-compilation-2026-11-07.
Fresh exact-head full app/package and every required native configuration and
integration gate remain mandatory before merge; local improvements waive none.

## Combined qualification amendment — 7 November 2026

The owner-authorised E08 integration follows
[release-source-convergence-2026-11-07.md](release-source-convergence-2026-11-07.md).
The exact unit history remains an ancestor of the combined source. Incorporate
all reviewed units before publication of the integration candidate and require
all original positive, negative, mutation/restoration, source/pin and full CI
gates again on that single final source. This supersedes a requirement to merge
each intermediate source separately before assembling the next unit. Main
remains unchanged until the complete combined candidate qualifies. Original
failed/pending results retain their own SHA and outcome; no historical receipt
is retargeted or ceiling/deadline/selected assertion weakened. Owner-account
native execution and final release gates remain held.

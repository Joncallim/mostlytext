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

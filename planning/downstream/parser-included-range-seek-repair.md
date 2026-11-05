# Bound lexer seek work for many embedded-language ranges

## Owner outcome and baseline

Embedded-language parsing should not scan every earlier source range on each
lexer seek. This unit adopts only the already-reproduced binary-search repair
for tree-sitter 0.25.10. It does not solve Markdown's remaining full inline-tree
reparse or justify changing the editor's large-document fallback.

Application baseline 2dc95c3e20e12b4bd095825918593b0164cb0d20 (PR #79), pending
integration of PRs #77–79; live main remains 5c867c5c at intake. The runtime is
exact da6fe9beb4f7f67beb75914ca8e0d48ae48d6406 through SwiftTreeSitter
1b1c85e94df6421a0e4bdcb9f3afaddb16b75d43 and Neon
d58b074a067861161a1df6d5b42d700526d0e7dc. The old A harness and separate later
profile prove the linear seek cost while also proving that eliminating it leaves
substantial parser work. Retain those dated results without treating them as
current complete-editor measurements.

## Ownership and fixed behavior

Use an isolated owner tree-sitter fork at the exact runtime base. Change only
the internal ts_lexer_goto range-selection loop, plus focused component tests
and a patch manifest. Validated included ranges have nondecreasing end bytes.
Find the first range whose end exceeds the original seek byte using lower-bound
binary search, then retain the existing forward skip and position adjustment,
including empty ranges. Preserve EOF, point/byte behavior, encodings, parser
state, cancellation, query output, ABI and public headers. Invalid range lists
remain rejected by the original parser API. No new allocation or authority is
introduced; interval lookup uses logarithmic comparisons and constant storage.

Publish a tested immutable owner revision only after qualifying it. Pin that
revision through a manifest-only SwiftTreeSitter child and manifest-only Neon
child, using one canonical location for each identity in all app/vendor
manifests. Preserve all previous range/client/buffer repairs. Only the runtime,
SwiftTreeSitter and Neon pins may change; all other dependencies and grammar
bytes remain exact. Preserve original MIT/BSD texts and update inventory,
notices and SBOM. No upstream issue, comment or PR is authorized or required;
the retained upstream AI policy excludes agent submissions.

## Verification and slices

1. Inspect existing exact C trial scripts before execution. Reproduce baseline
   output and operation-count growth with the current Markdown scanner backport.
   Stage full Rust/corpus fixtures from their recorded tags in the isolated
   component checkout. Missing fixtures/network or compilation failures are
   setup failures, not parser correctness results.
2. Add a focused included-range seek control covering empty/adjacent ranges,
   gaps, EOF/past-EOF, both UTF encodings and non-ASCII source. Apply the narrow
   patch and compare actual parse/query trees with the same original runtime.
   Run the upstream Rust/corpus suite, the prepared differential/random-edit
   trials and Address/UndefinedBehavior sanitizers. Preserve every first failure.
3. Re-run all exact SwiftTreeSitter and owned Foundation/C client/component
   regressions Debug/Release. Measure only the synthetic component fixture under
   the current host load, record distributions and hashes, and distinguish those
   timings from native or whole-editor results.
4. Adopt pins and provenance, compile locally without GUI execution and run full
   hosted app/package/mostlytext CLI checks. Review exact head and merge after
   predecessors pass. Update owning issues with limits and immediately audit all
   open issue contracts.

## Stop conditions and residual limits

Do not ship if range selection, tree/query output, encodings, sanitizer results
or previously repaired ownership differs. Do not weaken a test, threshold or
known failure to qualify the patch. A full-suite failure requires a concrete
baseline comparison or remediation. Dynamic grammar redesign, pointer-equality
subtree shortcuts, per-injection trees, styling allocation changes, widened
edits and fallback changes are separate designs. Native EXECUTION_HOLD, complete-
editor timing, release signatures and rights/source-publication gates remain.

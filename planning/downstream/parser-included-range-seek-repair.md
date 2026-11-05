# Bound lexer seek work for many embedded-language ranges

## Owner outcome and baseline

Embedded-language parsing should not scan every earlier source range on each
lexer seek. This unit adopts only the already-reproduced binary-search repair
for tree-sitter 0.25.10. It does not solve Markdown's remaining full inline-tree
reparse or justify changing the editor's large-document fallback.

Initial architecture intake used app2dc95c3e20e12b4bd095825918593b0164cb0d20.
Current merged main is68801d650dbd174f1cbc810617b43e7c22afdffd after PRs77–79.
PR80, exact app85d138d58797a9cbb4f2a4b1c79d536a4ae5daab, is the required next
predecessor and is in complete hosted qualification. It pins SwiftTreeSitter
7d2dc87e8b9326062d75bc1ef985f17d28e94da9 and Neon
be25e35787585430f0f1ac845ed44c11e7f8150a. Do not merge this unit until PR80
passes and integrates; merge that actual main without losing any prior repair.
Runtime baseline remains exact0.25.10 da6fe9beb4f7f67beb75914ca8e0d48ae48d6406.
The current owner fork changes only lexer range lookup, its test and manifest.

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

## Baseline failures and two distinct verification contracts

The first raw-unit edit corpus can split encodings and fails unmodified runtime
fresh equality; retain it as a diagnosed fixture-domain limitation, not evidence
that all edits are valid. A separate valid-scalar corpus keeps UTF-8/codepoint
and UTF-16/surrogate boundaries and also reproduces an original UTF-16 inline
reuse discrepancy at edit1018. PR80 independently reproduces the same class
through actual Markdown root/inline layers and selects explicit fresh parsing
only for MarkdownInline. It keeps a strict2,000-edit application fresh oracle.

The original fail-fast C fresh oracle is retained unchanged. A distinct all-step
behavior collector now runs all6,000 edits across UTF-8, UTF-16LE and UTF-16BE.
It counts every fresh divergence and RETURNS NONZERO if any occur. Both original
and candidate return2 with exactly282 discrepancies; all6,000 actual/fresh AST,
point, missing-node and query-capture traces are byte-identical, including each
diagnostic. This is runtime behavior preservation, not6,000 fresh-equivalent
edits. Sanitized traces must match too without sanitizer diagnostics.

The documented upstream cargo xtask test passes262 tests before/after. Broader
workspace validation passes317 unit tests but fails5 Rustdoc examples due to
missing example variables/devgrammar; the exact same5 failures reproduce on
unmodified runtime. Preserve logs, do not disable examples or call workspace
validation fully green. These concrete baseline comparisons satisfy the stated
full-suite failure investigation requirement; the lexer patch is not claimed
to repair unrelated parser-reuse or documentation problems. Adoption still
requires current application-policy component suites, full hosted CI, pin and
licence checks and final exact-head review. No test assertion is weakened.

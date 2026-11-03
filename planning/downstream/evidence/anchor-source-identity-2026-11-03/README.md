# Complete-input anchor fingerprint evidence

The optimized Foundation-only driver compiles the unchanged production
MarkdownSourceFingerprint.swift alongside Benchmark.swift. It hashes native and
bridged strings with ordinary bytes plus Unicode scalars, three samples each,
and verifies every result against a separate CryptoKit Data-based oracle.
Results.json retains every sample and the production source digest.

These are warm fingerprint-component times on CORTANA; no application launches.
They do not measure complete parsing, cold-start behavior or peak memory, and
do not close #203, native acceptance or final performance budgets. Existing
MarkdownEngine documentation-ceiling tests remain unchanged.

The private source-bound module suite passes 133 tests/18 suites in Debug and
Release, without adapters or stubs. The old index guard fails the two Unicode
cases; the intermediate body/YAML-only guard fails delimiter/whitespace cases.
The final index requires the full-input fingerprint recorded by ParseEngine.

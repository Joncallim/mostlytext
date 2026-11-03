# Preserve the Go runtime notice in the D2 distribution

The D2 browser bundle embeds the publisher WebAssembly, which identifies Go
1.24.6 and contains Go runtime function names. The current inventory preserves
D2 and its 16 external module root texts but has no Go runtime component/text.
Add the complete Go 1.24.6 BSD-3-Clause root notice as a conservative runtime
attribution, backed by exact official archive/LICENSE hashes and a structural
inspection of the immutable publisher WASM (defined function/code linkage, not
string presence alone). No invented publisher rebuild or exhaustive rights claim.

Baseline: PR #41 source 6507808d, on main 760fdc83. Its independent source changes
are retained. Commit this contract before implementing the attribution tranche.

## Scope and authority

Only compliance inventory, captured license/evidence, deterministic audit tooling
and meaningful negative controls, generated notices/SBOM and supporting records.
Keep D2/WASM/font bytes, all package pins, source-offer status and unresolved
independent source/nested/font/RFN obligations unchanged. Never execute the D2
publication script, product code, native UI, signing or public source publication.
An optional standalone source WASM build may investigate reproduction in a fresh
owned fixture using the checksum-verified official toolchain and frozen sources;
a failed/different build is evidence, not permission to relabel provenance.

Bind all inputs by digest, validate WASM bounds/section structure, and show named
Go runtime functions actually map to nonempty defined code bodies. Preserve the
full upstream root license verbatim without substituting for file-specific duties.
The source-build graph is useful attribution context, not unique binary provenance.

## Verification and completion

Positive: exact npm/publisher WASM and official Go archive/license metadata;
negative: altered WASM/hash, malformed/truncated sections, function names that
lack a real defined code body, changed notice/toolchain binding. Ordinary inventory,
generation/SBOM, all compliance and supporting controls; strict release still
reports genuine blockers. Rebuild a locked compile-only Release resource bundle
and run the actual unchanged non-application notice reader over its shipped corpus.
Prepare a new manifested source-review snapshot if notices are included there;
never rewrite old receipts. Full hosted checks qualify the stacked source as
applicable. Update #14 with precise evidence; do not check broad LC completion.

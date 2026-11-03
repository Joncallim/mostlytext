# Reproduce parser runtime provenance and complete Webpack attribution

## Owner summary and baseline

The signed parser source can now reproduce every published JavaScript file and
source map byte-for-byte with its pinned toolchain. Use that concrete evidence to
identify the outer parser compiler and vscode-uri input, while preserving older
content-only reports as historical comparisons. Four retained Webpack runtime
source bodies also match a licensed generated reference exactly; distribute its
complete MIT notice without pretending the original Webpack version is known.
This is MostlyText #14 source/attribution work, not independent legal review.
Baseline: main 24aa79eadfdb4bbb4a98772f4402988881aa3d9d, fully qualified PR35.

## Scope and evidence

Allowed: compliance evidence/verification/projection tools and tests, inventory,
generated notice/SBOM artifacts, the offline Compliance workflow checks and
current planning/review documentation. No app,
renderer, dependency lock, native guard, source-offer status or release predicate
changes. No production Node dependency is introduced. All upstream build tools
and generated fixtures live in a separate owned evidence directory.

The parser packet must bind signed publisher source 293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4,
the actual package archive, Node 24.16.0, integrity-verified pnpm 10.30.3, the frozen
lock and esbuild 0.25.12. Compare complete member sets:96 JavaScript +96 maps, including
all 32 members previously connected to shipped Mermaid. Preserve all 1,753 original
source hashes. A portable wrapper calls the actual upstream generator/config in
its three parser configurations; it does not claim type/prepack or other packages.
A changed real parser source must build but fail artifact comparison; restoration
must reproduce all 192 members again. Record the failed Node 26 attempt rather than
patching inputs or disabling schema validation.

A separate Webpack5.88.2 reference build must match complete source-map content
for bootstrap and three runtime helpers, without code normalization. Bind those
hashes through the original composed Mermaid/parser map, requiring positive
mapped body-operation probes. Keep the emitting Webpack version unresolved and
never describe the whole compiler package as shipped.

## Projection and failure policy

Raw historical mappings and their digests remain unchanged. Generic content-only
candidate projection stays qualified. Only a validated, pinned reproduction
packet permits the specific vscode-uri 3.1.0 projection and esbuild 0.25.12 emitted-
runtime identity; missing/corrupt/wrong-toolchain/member-set proof must fail.
Unproved earlier path-browserify resolution stays qualified. Add one qualified
Webpack runtime-reference record, preserve the exact authentic copyright/full MIT
text and existing credits. Do not reinterpret Framer, Rough.js or font grants.

## Verification and completion

Replay the actual reproduction and real source mutation, complete Webpack source
matches and composed code probes. Add discriminating missing-proof, changed hash,
wrong compiler/member set/body/notice and false whole-package/emitter controls.
Run the complete compliance suite and source/map checks, deterministic generation,
compile-only locked Release and the actual Foundation-only notice reader against
the built corpus within the unchanged 2 MiB bound. Confirm runtime/pins unchanged
and strict artifact check still reports all six existing failures. Hosted
Compliance and exact merge-tree proof precede integration. Native/language,
independent review, source publication and signed-artifact acceptance stay open.

# Rebuild the recorded Graphviz backend in an isolated hosted runner

The existing source review identifies Graphviz, Expat, Viz.js and the compiler
image, but has not rebuilt the shipped backend. This unit tests that exact build
path on a disposable hosted Linux runner. A complete byte match would strengthen
the source correspondence available to the independent attribution review. It
does not decide rights, approve the source offer or establish native acceptance.

## Baseline and reconciliation

Start at main `1780fe1908843e1278e7d41c9702327503b60d5f`, MostlyText #14/#17.
The source audit pins four archives and the backend subject. PR59 verifies the
recorded compiler index and its AMD64 child. PR60 fixes read-only layer overlay
semantics. Those units intentionally did not execute a compiler. This new,
separate unit permits execution only inside an ephemeral hosted Linux build;
owner-account product execution and local Docker/OS setup remain held.

The original Dockerfile has two fresh Emscripten stages and no package-manager
installation. The publisher record has no DEBUG argument; retain its empty
default. Rebuild only `lib/backend.js`, before the independent npm/Rollup wrapper
step. The existing audit already binds the npm wrapper and shipped renderer.
Do not claim the complete distribution was rebuilt from a backend-only match.

## Inputs, boundaries and data flow

1. A standard-library Python preparer verifies the four already-recorded archive
   sizes/digests and reads only the exact Dockerfile, viz.c, pre.js and published
   backend from their pinned archives. Use bounded regular-file reads; reject
   duplicate/linked members. Never unpack an upstream source tree on the host.
2. Create a new owned build context with only Dockerfile, viz.c, pre.js and the
   two verified source tarballs. The original Dockerfile bytes remain retained.
   Change exactly both base-image tags to the recorded AMD64 child digest and
   both remote ADD instructions to COPY of verified local tarballs. Preserve all
   stage, working-directory, configure/make/compiler/link flags and output bytes.
   Record original and derived recipe hashes; refuse any unexpected recipe.
3. On a hosted Ubuntu AMD64 runner, pull only that digest, then build with fresh
   caches, no RUN network, no secrets/SSH forwarding, no Docker socket or host
   directory mounts in build containers. The checkout uses read-only permission
   and does not persist its credential. No private documents or signing material
   enter the five-file build context. Bound the job to 45 minutes.
4. Export the build result to owned runner scratch; read and hash backend.js
   without loading its JavaScript/WebAssembly. Compare the entire file with the
   exact npm subject. Always retain a receipt with sizes, hashes and equality;
   fail the job on any byte difference. No stripping/normalization, revised flags
   or guessed dependencies to force equality. Stop and reconcile a mismatch or
   missing toolchain input before changing the build architecture.
5. Retain logs and JSON receipts, not application/source/WASM artifacts, in the
   workflow. The existing public source archives are fetched as pinned inputs;
   this is no corresponding-source publication or app promotion. Keep failed
   attempts as evidence, and use fresh run/output identifiers for any correction.

The preparer/receipt verifier belong to compliance tooling. No product module,
dependency graph, runtime, inventory, notices/SBOM, source-offer state, release
guard or historical proof changes. No user-facing UI/strings, persistence,
document rendering behavior or accessibility/export contract changes.

## Slices and evidence

1. Commit this current-source contract before implementation. Implement the
   preparer and manual/path-scoped hosted workflow; test altered source archives,
   unsafe/duplicate selected members, unexpected recipe edits and complete-output
   mismatch with real failure behavior. Ordinary compliance tests stay offline
   and must not run Docker or download upstream inputs.
2. Verify the actual retained inputs locally without executing upstream code.
   Run all compliance controls and source inventory. Review the precise derived
   Dockerfile against the source audit. Push/open the scoped PR to execute the
   fresh hosted rebuild; preserve its first result and exact source head.
3. If successful, commit the bounded receipt and reproducible procedure, with an
   offline checker binding all pinned inputs/recipe/output hashes and original
   source/shipped bytes. Reject receipt mutations. Update the canonical issue
   checklist only for observed technical reproduction. Independent exhaustive
   linked-code/per-file rights, complete source approval, publication/anonymous
   retrieval, native and final signed-artifact criteria remain open.
4. Require exact-head Compliance and the hosted rebuild, no unresolved review
   threads, expected-head merge and actual merge-parent/tree proof. No app Release
   rebuild is needed when every product/distribution byte remains identical to
   the fully qualified source `24b19a9b`. Preserve clean detached worktrees and
   verify a recovery bundle before removing the merged branch.

Done means a reproducible hosted result and honest receipt, refusal controls,
scope checks and issue/document reconciliation. A backend match is technical
source correspondence, not publisher signature verification, historical
execution attestation, exhaustive runtime retention or independent clearance.

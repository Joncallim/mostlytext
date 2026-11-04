# Reproduce the complete shipped Viz.js renderer

The Graphviz backend now reproduces independently, but MostlyText ships the
outer Viz.js browser distribution. Rebuild its metadata and all three wrapper
formats using the frozen npm lock and compare every generated runtime file,
including the exact shipped `viz-global.js`. This strengthens technical source
correspondence for #14/#17 without deciding independent rights or source approval.

## Current source and boundary reconciliation

Baseline main `f11329a212fce50b6caf6aeae8cf7188e1e4141a` (PR64).
Keep the backend preparer, verifier and successful receipt unchanged. Its
original build code remains fixed. This separate unit adds a final wrapper stage
after that exact backend recipe. It executes the upstream metadata generator
(which loads the backend) only inside an ephemeral hosted Linux container, with
network disabled for build execution. It never runs output on the local Mac.

The original workflow uses Node `24.x`; captured npm publisher metadata says
Node `24.19.0`. Use the latter as an explicit reproducibility reference, without
claiming it identifies the unique historical builder. Its official Linux AMD64
archive is pinned by the captured Node distribution SHA-256 list. Record measured
Node/npm versions in the container. The source lock has 546 resolved registry
inputs, all from `registry.npmjs.org` with integrity records. Keep the entire
frozen workspace lock, source and upstream scripts/configuration intact.

## Execution contract

1. Reuse PR64's verified four archives and exact backend context; add only the
   same full source archive and pinned official Node archive to a new seven-file
   wrapper context. Read only regular, bounded, uniquely named selected members
   on the host. Preserve the original five-file backend context separately.
2. Verify package-lock bytes and require registry HTTPS/integrity for every
   resolved non-workspace dependency. Preserve and compare the lock hash before
   and after npm installation/build. Use upstream `npm clean-install
   --ignore-scripts`, with audit/funding requests disabled. Only this dependency
   installation RUN has ordinary container network; it has no host data or
   credentials. Build RUN instructions retain network=none. Do not forward
   secrets/SSH or mount owner paths/Docker sockets into build containers.
3. Copy the freshly reproduced backend into the original package location.
   Use upstream `touch lib/backend.js` and `make`; retain metadata generation,
   original Rollup/Babel/Terser configuration, source and frozen dependency lock.
   No minifier flags, source patches, output normalization or guessed inputs.
4. Compare all five generated files with the pinned npm archive: backend.js,
   metadata.js and dist/viz.js, viz.cjs, viz-global.js. Bind the last directly to
   MostlyText's current shipped resource. Fail and retain identities on any
   difference; reconcile missing inputs/version/behavior before revising scope.
   No fresh npm archive/provenance reconstruction is claimed.
5. Retain only JSON/text receipts and logs as hosted artifacts, with a 45-minute
   bound, read-only checkout and no persisted credential/shared cache. No runtime
   output, source-review archive or app binary publication. Preserve first failures.

The new preparer/comparator, offline receipt checker/tests, workflow and evidence
documentation belong to compliance tooling. No product, inventory, distributed
notice/SBOM, pins, source-offer state, release guard or original packet changes.
No UI/string, persistence, accessibility or export behavior changes. All separate
account/native/signing/exact-artifact and independent per-file/grant/source
publication gates remain.

## Slices and verification

Commit this contract first. Prepare actual retained inputs locally without any
upstream execution. Add offline controls for changed Node/source/lock/context,
missing/extra/linked/changed generated files and forged equality claims. Run all
compliance tests/inventory and verify unchanged protected trees/strict failures.
Then run the hosted complete build and preserve its actual result/source head.
If it matches, capture and pin a bounded receipt with current-source/image/Node/
recipe/lock/output bindings and adversarial mutations. Reconcile current review
documentation and #14's checklist only for observed technical results.

Require final-head hosted reproduction and Compliance, no unresolved threads,
expected-head merge, actual parents/tree and clean canonical fast-forward. A new
app Release build is unnecessary because all product/distribution bytes remain
identical to fully qualified `24b19a9b`. Verify an incremental recovery bundle
before deleting the merged clean branch; preserve detached worktrees/stashes.

Completion means all five exact generated runtime files reproduce with honest
reference/runtime measurements and refusal controls. It does not imply historical
publisher attestation, full npm archive reproduction, exhaustive retained-code
rights review, an approved corresponding-source offer or native acceptance.

## Reconciliation after the first hosted failure

First hosted run `41821191927` at `60a48b1d` passes actual-input preparation and
backend compilation, then npm fails with `EAI_AGAIN` resolving registry.npmjs.org
inside the build. Metadata/wrapper generation and comparison are not reached.
Raw run/artifact ZIPs, prepared identities and complete build log are retained;
do not substitute a retry or claim the wrapper reproduced. Ordinary Compliance
at that head and all 288 local tests pass; neither establishes build-network access.

Replace the dependency-install network exception with a complete, verified
offline package cache. This changes the network/data-flow assumption before
implementation; it leaves the frozen lock, packages and build scripts unchanged.
Fetch the 546 lock-resolved tarball records on the hosted runner with bounded
parallelism and byte limits, verifying each declared Subresource Integrity hash.
Require the fixed registry HTTPS URLs, validate archive bytes before any use,
deduplicate identical integrity objects and record a complete dependency receipt.
Keep this cache inside a new owned directory, with no credentials or source
execution. Preserve failed downloads rather than overwriting differing objects.

Copy only these verified package tarballs into the new context cache directory.
Inside a build RUN with network=none, populate npm's content-addressed cache from
the local tarballs with scripts/audit/funding disabled. Use the same upstream
clean-install with `--offline` and the explicit cache; then run upstream make as
before, without network. Reject missing/changed/extra package objects, frozen-lock
changes and any request for an unavailable input. No guessed package, resolution
change, host networking, added install script or relaxed output equality is allowed.

The original backend prefix remains identical. Every RUN now uses the build's
network=none; remove the ineffective dependency-network exception. Add negative
controls for package integrity, exact dependency-object membership and missing
offline inputs before another fresh hosted run. Preserve first-run evidence and
record the cache-population method/actual Node/npm versions honestly. This
supersedes only the original single-networked-install instructions above; all
other scope, acceptance and publication/native boundaries remain.

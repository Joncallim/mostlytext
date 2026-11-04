# Record Graphviz's actual linker inputs without changing its output

The complete shipped renderer reproduces, but the compiler/runtime review still
lacks an object-level link record. Capture the linker's own map and archive
extraction reasons in a disposable hosted build, then require the complete backend
to remain byte-identical. This gives the attribution reviewer concrete archive/
member references while preserving the open independent rights/source review.

## Baseline and reconciliation

Start at main `aea2316033952633bddcdf237f193271b66fda4a`, MostlyText #14/#17.
PR64 reproduces the exact backend; PR65 reproduces all five generated runtime
files. PR66 changes only documentation. Reuse the pinned four source archives,
AMD64 image and unchanged backend preparation. Preserve every original receipt.

The existing direct library list does not describe every implicit system input.
LLVM's [WebAssembly linker options](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.6/lld/wasm/Options.td)
provide `-Map` and `--why-extract`. Its [map regression fixture](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.6/lld/test/wasm/map-file.s)
documents the map columns. This is an option/format reference, not a claim that
the captured SDK is LLVM 21.1.6; actual compatibility must be tested.

## Allowed data flow and failure behavior

1. Keep the original five-file backend context and metadata intact. Create a
   separate context from those verified files. Derive its Dockerfile by adding
   exactly one `-Wl,-Map=/output/backend.map,--why-extract=/output/why-extract.tsv`
   argument to the original final emcc invocation. No optimization, debug,
   source, library order, symbol export, working-directory or runtime flag changes.
   Verify the derived recipe/context again before accepting results.
2. Build only in ephemeral hosted Linux with the same fixed image, no RUN network,
   shared cache, owner data, secrets/SSH forwarding or build-container host mounts.
   Read-only checkout, no persisted credential and a 45-minute limit remain.
   No local Docker setup or product/upstream execution on the Mac.
3. Hash/compare all backend bytes with the pinned npm subject without loading JS/
   WASM. Any mismatch or unsupported flag fails and preserves its actual evidence;
   reconcile before revising the instrumentation. Do not change build behavior
   or normalize output to obtain equality.
4. Retain bounded regular UTF-8 linker sidecars, original raw bytes and their
   hashes. Validate the map header and three-column extraction table; preserve
   every reason row, archive/member identity and unexpected/non-archive case.
   Derive a sorted archive/member index and explicit map-versus-extraction counts
   from raw data. These files describe the wasm-ld stage, before any later
   Emscripten/Binaryen processing. Extraction is not final retention, and a map
   is not a per-file licence decision. Never infer a new shipped component or
   absence solely from a symbol/object name.
5. Capture only text/JSON maps, receipts and logs as artifacts, never JS/WASM,
   application binaries, source archives or private data. Keep each failed and
   successful run separately. Temporary compiler paths may vary between builds;
   preserve raw bytes and compare stable archive/member identities separately,
   without claiming raw-sidecar byte equality after normalization.

The new tooling, workflow, offline controls and evidence documentation own this
unit. Product, inventory, notices/SBOM, pins, release predicates, source-offer
states, original inputs/receipts and native/signing holds remain unchanged. No UI,
localization, persistence, accessibility or export behavior changes.

## Slices and completion

Commit this contract before implementation. Add exact recipe/context checks and
adversarial parser/receipt/output controls. Locally prepare retained inputs and
run offline tests/inventory without upstream execution. Run the hosted diagnostic
build and retain its first result. If output equality holds, commit raw sidecars,
the observed index and pinned receipt with a separate offline verifier that binds
the current image/source/recipe/tool/output. Recompute the index from captured raw
bytes; test malformed/changed files and false stage/scope/equality claims.

Require final-head hosted diagnostic and Compliance, no open review threads,
expected-head merge and actual parents/tree proof. Product/distribution trees
must still equal qualified source; a fresh app Release build is unnecessary for
this evidence-only change. Verify recovery bundles before removing merged clean
branches; preserve worktrees and stashes. Update #14's checklist only for observed
link-stage evidence. Independent exhaustive per-file/grant review, complete source
approval, separately authorized publication/anonymous retrieval, native and exact
signed-artifact acceptance remain open.

## Observed diagnostic result

Runs `41850441841` (`6653ed2e`) and `41850608058` (`c367af8b`) both preserve
the complete backend bytes. The latter captured receipt records 9,874 map rows,
426 mapped archive/member pairs across 17 archives, and all 577 extraction-reason
rows covering 457 distinct pairs. There are no unparsed extracted inputs; 32
mapped pairs lack extraction records and 63 extracted pairs lack map records.
These differing sets are retained, not reclassified as final retention. Both runs
agree on stable member sets; raw diagnostic hashes differ with temporary paths.

The map names libc++/libc++abi alongside libc, compiler-rt, allocator/stubs and
Graphviz/Expat. This identifies a concrete separate source/text reconciliation
unit without approving its per-file obligations here. Twelve offline methods
now cover bounded parsing, raw preservation, exact recipe/index/receipt bindings
and false scope/output/rights claims. Final-head hosted qualification remains
required after the evidence additions. No distribution/release predicate changes.

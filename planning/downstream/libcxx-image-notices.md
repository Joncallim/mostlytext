# Preserve the recorded compiler's complete C++ runtime root notices

The actual Graphviz link map names libc++ and libc++abi archive members, while
the notice corpus currently has only Emscripten/musl and compiler-rt root records.
Preserve the two C++ runtimes' complete root licence texts and referenced partial
credits from the recorded compiler image. This closes a concrete text-coverage
gap without treating root notices as an exhaustive per-file or rights review.

## Baseline and dependencies

Live main is `aea2316033952633bddcdf237f193271b66fda4a`. This branch uses stable
PR67 head `3a71068a19bfefe8b65e4c38b627ee1028f93d32`, whose pinned map/receipt
and offline verifier are the exact dependency interface; require its merge before
this unit merges. Its map names ten libc++-noexcept and eight libc++abi-noexcept
archive members. That is wasm-ld-stage evidence, not proof of final optimization
retention. Existing complete renderer and backend reproduction remain intact.

A read-only discovery in the previously verified SDK layer finds each runtime's
LICENSE.TXT and CREDITS.TXT. libc++ root licence is 16,703 bytes; libc++abi is
16,706 bytes. Both retain complete modern and legacy portions. Do not select a
convenient subsection, infer unique source Git provenance or substitute one
runtime's similar text for the other. Qualify actual final image files first.

## Data and ownership contract

1. Replay the existing compiler index/child/config and all four compressed and
   uncompressed layer identities. Use the existing corrected bounded selected-file
   overlay reader for exactly the four runtime root files. Check later replacement/
   whiteouts and selected links; never extract a root filesystem or execute image
   code. Capture actual final bytes with supplying layer identities.
2. Compare those complete files with the immutable Emscripten source-reference
   commit already used for compiler-rt, recording exact byte/Git identities when
   they match. Preserve differences explicitly; no guessed revision or grant.
   Actual recorded-image bytes are authoritative for this selected text capture.
3. Add two clearly scoped `kind: attribution` records, with all four unchanged
   texts and complete modern/legacy root terms. Use distinct complete-root licence
   references, honest image/source-reference resolution and explicit link-stage/
   per-file limits. Preserve every earlier component, notice and source-offer
   field. Regenerate notices/SBOM in the same change; no runtime or dependency pins.
4. Add an offline verifier binding image graph, root text bytes, complete link
   packet, exact archive/member subsets, inventory and generated notice coverage.
   Optional raw-image replay must verify full layers and final selected bytes.
   Controls reject missing/partial/swapped texts, fake linkage/coverage and altered
   image provenance. No independent rights or complete source-offer approval.
5. Build the locked universal Release app without launching it, compare the actual
   bundled notice with source and read it through the unchanged Foundation-only
   notice reader. Run resource/artifact inventory and preserve the same six strict
   failure messages. Require complete hosted Mac source CI and Compliance at the
   final head, including ordinary package/non-UI tests and Debug/Release builds.

Only compliance inventory/texts/generated outputs, focused verifier/tests/evidence
and review documentation change. Product code, runtime files, package locks,
release guards, historical receipts and native/signing holds remain. No local
app/CLI/helper or AppKit/WebKit execution. Public source archive publication and
exact signed-artifact inspection retain their separate gates. UI/localization/
persistence/export behavior does not change; build-only evidence is labelled.

## Completion and stop conditions

Commit this architecture before implementation. Qualify the actual four image
files and source-reference comparisons before inventory edits. Stop/reconcile an
unexpected image/link/source mismatch or insufficient notice budget; do not
weaken a guard or elect unproved terms. Retain first failures before corrections.
Finish with exact-head CI, no unresolved reviews, expected-head merge, actual
tree/parents and clean canonical fast-forward. Verify recovery bundles before
deleting merged clean branches; preserve worktrees/stashes. Update #14/#17 only
for completed text/source/resource evidence. Independent per-file/grant review,
source approval/publication/anonymous retrieval, native and final signed-artifact
acceptance remain explicitly unfinished.

## Qualified selected-source result

PR67 merged as `dbbd6f4f69d3f4712801205cbd92308d9244870d`; its actual tree equals
the stable dependency used here. Full raw image graph/compressed/uncompressed
layer replay and ordered final-file readback pass. All four selected root files
come from SDK layer `9fb8c7e6...`, with no later selected replacement/whiteout,
and equal the named Git source reference byte for byte. The baseline corpus lacks
all four complete texts. New records preserve 39,193 bytes of complete root texts
and partial credits while every previous component remains unchanged.

The first focused verifier run exposed an overly literal coverage comparison for
the source credits' two terminal newlines. The existing notice generator uses
`rstrip`; correct only the verifier to that existing presentation projection and
retain exact byte hashes for the four files. Its failure is preserved. This is
not a text truncation or a change to generator policy. All seven focused controls
and the complete 314-control suite now pass; raw-image replay passes. Resource,
full hosted source CI and final-head merge gates above still apply.

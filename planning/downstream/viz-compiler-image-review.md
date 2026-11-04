# Bind the recorded Viz.js compiler image without executing it

The publisher's build record names a Docker digest and linux/amd64, while the
current conservative runtime-source notices use an immutable Emscripten source
reference. This unit checks the actual recorded image graph and selected source
files so independent review can distinguish an image index, its platform image
and the files actually present. It does not run a container/compiler, rebuild
WASM or infer which runtime objects survived linking.

## Baseline and false assumption

Start at main `dc6ca9d4dba7d1596193534da7d6b0a0acf9d48d`, MostlyText #14.
The recorded `4e332f...` digest is a multi-platform manifest list, not itself the
linux/amd64 image manifest. It resolves that platform to `c2ac84...`; both
identities must be retained. Existing publisher provenance remains a cross-checked
build record without signature verification. Do not rewrite its original bytes.

## Allowed investigation

1. Fetch the public registry's immutable index, the linux/amd64 manifest and its
   config. Check response bytes against every SHA-256 and platform/size identity.
   Bind these objects to the existing verified package/backend publisher record.
2. Read the four image layers, bounded to the recorded 822,423,251 compressed
   bytes (under 1 GiB), within the owned capture. Verify every compressed digest
   and the config's uncompressed diff identifiers. Never launch image binaries,
   run a container, extract an image over host paths or change Docker/OS setup.
3. Stream tar records without filesystem application. Whitelist the six existing
   Emscripten compiler-rt/link/source inputs, version and SDK configuration files.
   Apply ordered replacement/whiteout semantics for those selected paths; reject
   selected links/ambiguous paths. Record which layer supplies each final byte.
4. Compare the selected actual image files against the existing conservative
   source reference and distributed notice bytes. If they differ, stop and record
   the mismatch before any license, attribution or source-offer decision. No
   arbitrary version/license promotion or inference of complete linked-code audit.
5. Preserve raw metadata and selected bytes locally; add a pinned, read-only
   offline proof and deterministic refusal controls for the graph and selected
   file binding. Reconcile the current review packet and issue with observed
   results. Keep runtime, pins, inventory, notices/SBOM and release guards intact
   unless a separately reconciled evidence-backed correction is required.

## Verification and completion

The deliverable is a fully digest-checked platform/image/layer graph, selected
file identity correspondence, replay recipe and refusal evidence. Use Python
source/evidence checks and hosted Compliance. This evidence-only scope requires
no product or app-target execution, local native account, new infrastructure,
source publication, signing or private credentials. Independent per-file/source/
rights review, native acceptance and all six strict release predicates remain.

## Capture reconciliation before verifier implementation

All four compressed layer hashes and all four uncompressed config diff identifiers
verify. The selected-source readback finds the root licence, credits and three
link/driver sources byte-identical to the earlier reference. The sixth file is
deliberately different: the image contains `"5.0.7"`, while the retained Git
reference contains `5.0.7-git`. Preserve and report both hashes; do not normalize
them into equality or alter the original reference manifest. This mismatch calls
for no license choice because both actual complete licence/credit texts match.
The new verifier must require five exact source matches and that explicit version
marker difference, rather than claiming all six inputs are byte-identical.

The compiler digest in the publisher record is the multi-platform index
`4e332f...`; its AMD64 child is `c2ac84...`. The actual SDK configuration names
Node 22.16.0, LLVM/Binaryen roots and SDK release mapping 5.0.7 to
`6cd98e86d7749ff98b82b7f2ae78eb4f01942788`. These are image file/configuration
facts, not independently executed compiler versions or a unique Git origin.

## Qualified result

The complete four-layer graph is verified at compressed and uncompressed levels,
with ordered selected-source readback. Nine final files are captured: the five
matching source/text inputs, explicit differing release marker and three SDK
configuration/manifests. Twelve offline graph/overlay/refusal controls pass. The
portable capture and raw replay exercise the recorded public blobs without
Docker, image execution or host filesystem application. No distribution, original
manifest, notice/SBOM, source-offer or release predicate changes. See
[the image packet](../../compliance/evidence/viz-compiler-image/README.md).

## Overlay correction contract — 4 November 2026

Baseline main `cf4355c751576054a68ea5d814c095a2051019e4`, MostlyText #14/#17.
A source review found that the reader applied deletion markers to files already
read from the same layer. That makes a late opaque marker incorrectly hide an
upper-layer replacement. The [OCI image-layer specification v1.1.1](https://github.com/opencontainers/image-spec/blob/v1.1.1/layer.md#whiteouts)
requires whiteouts to affect only lower layers, independently of tar order.
The pinned image has no selected-path whiteouts; its existing proof is unaffected.

Keep the inherited selected-file map separate from each layer's additions.
Apply ordinary and opaque whiteouts only to inherited records, then overlay the
current layer's bounded, unique regular files after that layer has been read.
Continue refusing selected links, unsafe paths, non-directory ancestors,
duplicate selected records and oversized reads. No host filesystem application,
container execution or additional source selection is permitted.

Before changing the reader, add deterministic ordinary/opaque marker controls
covering both archive orders, replacements and new nested files, first-layer
additions, removal of lower siblings, and removal by a subsequent layer. Retain
actual failing-before assertions. Then run all Compliance controls and replay
the original four compressed/uncompressed layers and nine selected source files.
Keep every pinned evidence/manifest, notice/SBOM, inventory, runtime byte and
release predicate unchanged. Hosted Compliance and exact merge-tree evidence
complete this scoped tooling correction; native and independent rights review
remain in their owning issues. No app Release build is needed for Python-only
evidence tooling with no distribution input changes.

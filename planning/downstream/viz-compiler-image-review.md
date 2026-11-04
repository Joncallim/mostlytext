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

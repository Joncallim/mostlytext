# Recorded Viz.js compiler image: graph and selected-source proof

The compiler digest recorded by the Viz.js backend publisher now has a fully
verified image graph and selected-file readback. The complete compiler-rt licence,
credits and three link/driver source files inside its Linux AMD64 image equal the
previous conservative source reference byte-for-byte. The release marker differs
and is preserved explicitly. This narrows the compiler-source attribution gap;
it is not a WASM rebuild, proof of linked-object retention, independent per-file
rights review or source-offer approval.

## Index, image and layers are distinct

The [original backend record](../viz-js-3.30.0/source-audit.json) names
`emscripten/emsdk:5.0.7` with linux/amd64 and digest
`4e332f7343b6f66320bf72f7ecc01a3d9f3866721a13b0e5c7b96505d6ab148a`.
That digest identifies a **multi-platform manifest list**. Its AMD64 child is
`c2ac84c26ee40ae2f2c5a15bd3f9e608d1959e1b37413fa7f08138046a188dc5`;
the child config is
`f8b9ec6ea64ccb381d9a9553146fa265eeb72b8a5283d582bb6f492a1f6385f0`.
All raw response bytes match these SHA-256 digests; no mutable tag is substituted.
The config also declares Linux AMD64.

All four compressed layers, totalling 822,423,251 bytes, match the child manifest.
All four uncompressed tar digests match the config's ordered filesystem diff
identifiers. The [layer receipt](layer-verification.json) records both levels.
Every selected final source comes from the same SDK layer. Later layers contain
no selected-path replacement or whiteout. The reader handles later replacement,
whiteouts and opaque directories, refuses selected links/ambiguous paths, and
never applies an image filesystem to host paths.

## Actual file correspondence

| Selected image input | Comparison with earlier source reference |
|---|---|
| `system/lib/compiler-rt/LICENSE.TXT` | Exact complete 16,708-byte match; distributed text unchanged. |
| `system/lib/compiler-rt/CREDITS.TXT` | Exact complete 1,049-byte match; referenced partial credits unchanged. |
| `tools/system_libs.py`, `tools/link.py`, `emcc.py` | All three complete files match the existing immutable reference. |
| `emscripten-version.txt` | Image bytes are `"5.0.7"` plus newline, SHA-256 `63f302ebe7ed904608943bc13d2abe2653f9ccc444fe47046409b680db5614dc`. Earlier Git-reference bytes say `5.0.7-git`; those are different and are never normalized into equality. |
| SDK configuration and two manifests | Captured as three additional final image files. Configuration names LLVM/Binaryen roots and Node 22.16.0; the SDK release map binds 5.0.7 to `6cd98e86d7749ff98b82b7f2ae78eb4f01942788`. No image executable was launched to claim a measured tool version. |

The [nine-file receipt](selected-files.json) includes full byte counts/hashes,
originating layer identities and all six explicit comparisons. The original
[compiler-rt source-reference packet](../compiler-rt-source-notices/README.md),
its Git identities, notice/inventory fields and original publisher records remain
intact. The image file match strengthens those selected source/text bindings;
it does not establish a unique source Git revision for every SDK file.

## Replay without Docker or native application execution

No Docker installation, container execution, upstream compiler or native app/test
account is used. Anonymous public registry access obtains only the recorded
metadata/blobs. The capture checks exact digests and size limits and saves no
registry authorization token. It refuses to overwrite differing retained
metadata. The reader streams bounded source records from tar files without
extracting a root filesystem.

```sh
python3 compliance/evidence/viz-compiler-image/capture.py \
  --output /path/to/owned-image-capture
python3 compliance/tools/verify_viz_image.py --inputs /path/to/owned-image-capture
python3 -m unittest compliance.tests.test_viz_image -v
```

The local raw capture is retained at
`/Volumes/Fast SSD/CORTANA-Builds/viz-compiler-image-20261104`.
`--inputs` independently hashes every compressed layer and uncompressed diff,
then rereads the selected files with overlay semantics. Ordinary offline CI
checks the [pinned metadata and receipts](manifest.json), the original publisher/
renderer/notice binding and refusal controls; it downloads or runs no image.

Controls reject altered graph bytes, coherently hashed wrong platforms/incomplete
layer graphs, wrong layer order/diff identifiers/sizes, partial/changed selected
files, a false version-marker equality, later whiteouts, linked/duplicate/unsafe/
oversized source records and missing proof. Positive overlay controls establish
correct later replacement while leaving host paths untouched. The subsequent
[overlay correction](../../../planning/downstream/viz-compiler-image-review.md#overlay-correction-contract--4-november-2026)
keeps each layer's additions separate until its whiteouts have affected only
inherited files. Four regression methods cover both archive orders, same-layer
replacement/nested additions, first-layer additions and subsequent-layer removal.
Seven assertions fail against the original reader; the selected raw image files
contain no affected whiteouts and retain their original hashes.

## Remaining review

The publisher build record remains cross-checked, not signature-verified. The
complete image graph is identified, but no Graphviz/WASM output was rebuilt, no
library/object retention was inferred, and complete compiler/sysroot/per-file
attribution review remains open. No libc++ or libunwind record is added merely
because a source file exists. Existing full license texts, runtime, pins,
inventory, generated notices/SBOM, source-offer flags and all six strict release
predicates remain unchanged. Source publication, native acceptance, signing and
exact final artifact verification retain their own gates.

# Selected Go standard-library notices — 4 November 2026

The D2 source-build input graph selects 192 standard-library packages and 1,013 Go/
assembly files from the verified official Go 1.24.6 archive. This supplement
preserves 22 distinct Go copyright lines, three byte-distinct Sun notice blocks,
one complete Cephes notice/readme excerpt shared by five files, one complete
fiat-crypto notice, the complete Go root license and Go/PATENTS. Twenty-one selected
files carry the supplemental foreign comments. Byte-identical texts are deduplicated;
every original selected path, file hash and comment byte range is retained in the
[manifest](manifest.json). No comments are rewritten as a newly invented grant.

[The notice corpus](../../licenses/d2--GO-STDLIB-SUPPLEMENTAL.txt) is an explicit
conservative source-build attribution. It is separate from the [actual selected
runtime code linkage](../d2-go-runtime/README.md). A local graph from the publisher's
reported source and official toolchain is not proof that every selected file was
emitted, a unique original adaptation/grant attestation, a publisher rebuild,
complete nested runtime/source clearance or source-offer approval.

## Reproduction and exact inputs

The official archive SHA-256 is
`4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a`.
The original captured Go graph SHA-256 is
`505017100487dc73230d6d95b2788c37f1f5192a17db11f8a07d4786e1962acc`.
The normalized path/package selection SHA-256 is
`0aa0c071a6fd8dcc4e200cf21bcdd2f25b53dcb6a00d63afc3d2cf9ac63b352c`.
All selected file bytes are read directly from the verified archive in one pass.
The four vendor root licenses are byte-identical to go/LICENSE; no additional
unreviewed license choice is inferred. The existing D2/npm/source audit remains
unchanged, as do shipped JS/WASM/font files and package pins.

With INPUTS set to the retained d2-source-148-2026-10-20 input directory:

```sh
python3 compliance/tools/prepare_go_stdlib_notices.py \
  --go-list "$INPUTS/d2js-wasm-go-list.json" \
  --go-archive "$INPUTS/go1.24.6.darwin-arm64.tar.gz" \
  --manifest /tmp/go-stdlib-manifest.json --notice /tmp/go-stdlib-notices.txt
cmp compliance/evidence/go-stdlib-source-notices/manifest.json /tmp/go-stdlib-manifest.json
cmp compliance/licenses/d2--GO-STDLIB-SUPPLEMENTAL.txt /tmp/go-stdlib-notices.txt
python3 compliance/tools/verify_go_stdlib_notices.py
```

The corpus is 7,868 bytes, SHA-256
`1631d50a03dbd23f8ad778ea20f87f6944eb9bc34e6a662e63e95b38d2aa51ac`.
The manifest SHA-256 is
`d75dfd5102bcbb4a829b3d2b4091aa3e537349d9d76aa1f84ce2be3ab479ae8d`.
The offline verifier binds that captured manifest, exact component record,
reconstructed text and generated distribution corpus. It rejects coherent
manifest/text rewrites and unsupported stronger binary-provenance claims.

## Verification and limits

Ten new methods cover complete assembly, truncated/changed corpus, coherent
manifest rewrite, missing/duplicate inventory records, a changed source selection,
and removal of the actual Sun condition, Cephes free-use/disclaimer or fiat-crypto
condition/disclaimer. All 218 compliance tests pass. Real preparation repeated
against the unchanged archive and graph yields byte-identical manifest/text.
The locked compile-only universal Release succeeds. The ordinary actual-artifact check and unchanged Foundation production reader
pass against compiled resources: 151 components, 100 added build/runtime credits,
476,521 notice bytes under the unchanged 2 MiB bound. The refreshed 25-file
Graphviz source-review snapshot is verified at a new path, SHA-256
`eed89107fdaffab73c26cd2ae15aa1fcee57753ad58a3543f12c5589e2f88784`;
older snapshots remain intact and none is approved or published. Hosted
Compliance is collected on the exact source before merge. No application, archived
D2 code or WASM is executed. The six existing strict release gates remain required.
Raw controls and compile evidence: `/Volumes/Fast SSD/CORTANA-Builds/go-stdlib-notices-20261104/`.

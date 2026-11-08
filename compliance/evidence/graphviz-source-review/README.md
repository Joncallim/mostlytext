# Graphviz local source-review package — 4 November 2026

> Private-path review — 9 November 2026: the dated archive below copied five
> reproduction READMEs with local build-machine paths. It remains historical
> review evidence and must not be used as the public source package. The current
> assembler removes only those five paths from its package copies, preserves the
> repository's original evidence, and rejects any other local user/volume path
> in the assembled non-upstream material. Its newly verified, unpublished
> 58-member package has SHA-256
> `f2fba2c66a79f3345cc2db1eca515ae570175904f1b96449edf9937c4341d8b2`.
> The versioned private stage verifies this package and still claims no public
> retrieval, source completeness, rights clearance or application release.

The exact Graphviz 16.0.0, Viz.js 3.30.0, Expat 2.8.4 and npm renderer inputs now
have a deterministic local review archive. It includes current notice/SBOM
snapshots, the recorded source/build audit, selected nested notices and explicit
review limits. It has not been approved as the complete corresponding-source
offer and is not published. No MostlyText application binary or private material
is included. The already-public npm renderer input is JavaScript/WebAssembly.

Archive SHA-256: `e9db382f36e79f5153c1c31a32700084327ea735fb51dd811293116d648923ca`. It contains 57
manifested files plus manifest.json; all bytes and exact member sets are verified.
The [manifest](manifest.json) records each size/digest. Local artifact:
`/Volumes/Fast SSD/CORTANA-Builds/libcxx-image-notices-20261104/graphviz-source-review-image-link-cpp.tar.gz`.

This snapshot adds 24 exact committed compiler-image, backend/wrapper
reproduction, link-map/extraction and C++ notice evidence files, plus both C++
inventory records and all four complete root licence/credit texts. The assembler
first replays their installed offline verifiers and the original source audit.
Every included evidence path retains its repository path beneath
`evidence/reproduction/`; no raw image layer or compiled application is included.
The receipts are review evidence, not a self-contained compiler environment.
Their source/build and pre-optimization/link-stage limits remain unchanged.
The current global notice/SBOM snapshot contains 155 components.

The preceding 29-file compiler-rt snapshot remains untouched at
`/Volumes/Fast SSD/CORTANA-Builds/emscripten-runtime-20261104/graphviz-source-review-compiler-rt-qualified.tar.gz`
(SHA-256 `538e76c405ecd52026de1bfcd67428b951745a5a0c86223f47f99e4ee2489613`).

## Reproduce and verify

With the retained graphviz-inputs directory documented in
[the upstream audit](../viz-js-3.30.0/README.md), run:

```sh
python3 compliance/tools/prepare_graphviz_offer.py \
  --inputs /path/to/graphviz-inputs --output /tmp/graphviz-source-review.tar.gz
python3 compliance/tools/prepare_graphviz_offer.py \
  --inputs /path/to/graphviz-inputs --output /tmp/graphviz-source-review.tar.gz --verify-only
python3 -m unittest compliance.tests.test_graphviz_offer
```

The assembler replays the existing exact source/bundle/build/notice audit before
packaging, normalizes archive metadata/times without changing input bytes, and
refuses to overwrite a different archive. Verification rejects duplicate, extra,
missing, traversal, non-file and corrupted members. No archive content, npm
package, upstream shell script or compiler image is executed.

## Remaining review and publication

Independent source/build and embedded runtime review, required compiler/sysroot
inputs and complete per-file notices remain open. Bison's source exception and
Emscripten/musl root texts are preserved, not treated as exhaustive runtime
coverage. A source-review archive is not an independent rebuild or legal clearance.
The later [hosted backend rebuild](../graphviz-backend-reproduction/README.md)
does reproduce the complete npm backend byte for byte from its recorded inputs.
That technical correspondence does not approve this dated source-review archive
as complete or resolve the remaining independent/runtime/publication obligations.
D2's separate verified review archive is documented in
[its checkpoint](../d2-0.1.33/README.md).

[ARCHIVE_PLAN.md](../../ARCHIVE_PLAN.md) still requires explicit source-archive
publication authorization, stable hosting and anonymous download verification.
No source-offer status changes; the strict release check remains blocked.
Current notices/SBOM are a dated distribution snapshot. If those inputs change,
prepare a new package and manifest rather than reusing these hashes.

The earlier PR25 review package is retained separately at graphviz-source-review-final.tar.gz
(SHA-256 `fc35780d174b0a9519000b22a952300dfd49bf7f001586cf7b9417fef9706c5e`). This later snapshot includes the
Thenable notice; upstream/source and approval limits are unchanged. No old local
archive is overwritten.

The prior Thenable review snapshot (SHA-256 `e045615c9d9db048eb689a1eb7b595cc78975935c9b7357526ed9c229fd449e5`)
remains at graphviz-source-review-thenable.tar.gz. The current snapshot also
includes the qualified parser-runtime MIT notice; source/review limits are unchanged.

The prior 97-credit runtime snapshot remains at graphviz-source-review-esbuild.tar.gz
(SHA256 d0733acf3a662540ef755c92bd96815a9313e089d36a7a64055d4385370ca9a8).
The current snapshot includes the reproduced parser-input labels and qualified
Webpack MIT notice. Every upstream/source input and all review/publication limits
remain unchanged; no old archive is overwritten.

The 4 November Go-runtime notice update prepares another 25-file snapshot with
the then-current 150-component notice/SBOM corpus. The previous parser/Webpack archive
remains intact at its recorded path/hash. This package is still unapproved and
unpublished; its notice snapshot does not complete runtime/source review.

The later selected-Go-standard-library notice supplement refreshes the global
snapshot to 151 components. The preceding Go-root archive and parser/Webpack
archives remain untouched at their earlier paths and hashes. The current snapshot
is still a local review package, not an approved or published source offer.

The previous selected-Go-standard-library archive remains unchanged at
`/Volumes/Fast SSD/CORTANA-Builds/go-stdlib-notices-20261104/graphviz-source-review-go-stdlib.tar.gz`
(SHA-256 `eed89107fdaffab73c26cd2ae15aa1fcee57753ad58a3543f12c5589e2f88784`).
That 152-component checkpoint added the complete compiler-rt root licence,
its referenced partial contributor credits, captured source-link evidence and
offline verifier. The current image/link/C++ supplement above narrows the recorded
compiler evidence; complete per-file linked-code/source/rights review remains
open. This remains an unapproved, unpublished source-review package.

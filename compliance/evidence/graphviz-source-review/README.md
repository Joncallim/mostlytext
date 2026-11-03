# Graphviz local source-review package — 4 November 2026

The exact Graphviz 16.0.0, Viz.js 3.30.0, Expat 2.8.4 and npm renderer inputs now
have a deterministic local review archive. It includes current notice/SBOM
snapshots, the recorded source/build audit, selected nested notices and explicit
review limits. It has not been approved as the complete corresponding-source
offer and is not published. No MostlyText application binary or private material
is included. The already-public npm renderer input is JavaScript/WebAssembly.

Archive SHA-256: `165316d0ed75e8ec5beb4cf9569c900d7421a2454d19e4f5130e3637efacd240`. It contains 25
manifested files plus manifest.json; all bytes and exact member sets are verified.
The [manifest](manifest.json) records each size/digest. Local artifact:
`/Volumes/Fast SSD/CORTANA-Builds/d2-go-runtime-20261104/graphviz-source-review-go-runtime.tar.gz`.

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
the current 150-component notice/SBOM corpus. The previous parser/Webpack archive
remains intact at its recorded path/hash. This package is still unapproved and
unpublished; its notice snapshot does not complete runtime/source review.

# Distributed source-build reference notices — 3 November 2026

> Subsequent scoped update: [Thenable's explicitly declared MIT terms](../thenable-mit-declaration/README.md)
> are now assembled and distributed with the author's credit and positive mapped
> code probes. Earlier Thenable full-text linkage limitations below are historical;
> the other embedded-code and origin-review limits remain.


Twenty-two conservative attributions now preserve complete selected terms for
four Rough.js dependency inputs, 16 D2 Go-module inputs, the Bison skeleton text
in Graphviz sources and Emscripten/musl root notices. The [manifest](manifest.json)
records exact inputs, archive/source hashes, inventory projections and limits.
These are labelled source-build/reference attributions in distributed notices
and SBOM, not whole-package binary-retention or independent rebuild assertions.

## Rough.js

The mapped Rough.js prebundle already matches its official 4.6.6 package. Its
publisher gitHead 56a2762171b1294d643501e8d14f120db6b27bd7 supplies the package lock:
hachure-fill 0.5.2, path-data-parser 0.1.0, points-on-curve 0.2.0 and points-on-path
0.2.1. Exact source imports, lock integrity and official archives agree. Each
complete MIT text is included. This proves conservative source-build linkage,
not independent minified-function or exact original build reproduction.
points-on-curve additionally credits an offset-Bezier article. Its upstream
origin/terms remain a named embedded-source review lead; the root MIT label does
not silently clear it.

## D2

The existing verified D2 source-review archive matches all 16 recorded Go module
identities, ZIPs and complete root license texts. These texts now ship. FreeType-Go
uses its offered FreeType License option: both the original choice notice and
full FTL terms are included, with the required binary acknowledgment. Its retained
FTL file uses ISO-8859-1. The distributed UTF-8 copy preserves every character;
re-encoding it gives exactly the original bytes/hash. No replacement character,
license wording change or source-archive modification is introduced.
The separate Luxi test-data fonts are not identified as compiled packages by the
recorded graph and are not claimed as shipped fonts. The already-registered
Liberation Mono notice stays intact; its RFN and independent provenance review
remain open. The module graph is not proof that all compiled functions survive
linking or that the publisher WASM was independently reproduced.

## Graphviz compiler/parser references

Two Graphviz 16.0.0 distributed parser files share the exact preserved Bison 3.8.2
copyright/exception header; their Makefiles establish the source-build paths.
The full GPL-3.0 text and the existing Bison-exception-2.2 are included together.
This does not remove the exception, classify the entire application as GPL or
prove the publisher's exact generated parser output was reproduced.

The publisher backend record names emscripten/emsdk 5.0.7 and immutable image
digest. Emscripten's 5.0.7 reference resolves to
263db4cffa6f9fc2ec514a70abac81362ea41849. Its full root license (including Node.js
text), AUTHORS and musl COPYRIGHT are included. Per-file libc/libc++/compiler-rt
and other compiler/runtime retention still need review; root notices alone do
not prove exhaustive runtime obligations. Publisher/tag signatures were not
independently verified.

## Reproduction and controls

Ordinary CI validates the pinned manifest, installed record set, text hashes and
unchanged Mermaid/D2/Graphviz source reports. Full replay additionally checks the
four npm inputs and publisher lock, exact D2 review archive/module ZIP license
bytes, lossless FTL round trip, Graphviz parser/Makefile bytes and root references:

```sh
python3 compliance/tools/verify_build_attributions.py
python3 compliance/tools/verify_build_attributions.py \
  --rough-inputs /path/to/current-upstream-capture \
  --mermaid-inputs /path/to/mermaid-148-40b25974-2026-10-18 \
  --d2-archive /path/to/d2-source-review-bundle.tar.gz \
  --graphviz-inputs /path/to/graphviz-inputs
python3 -m unittest compliance.tests.test_build_attributions
```

Current upstream capture is local at
`/Volumes/Fast SSD/CORTANA-Builds/nested-notice-completion-20261103/upstream`.
Every external original is retrievable through its immutable manifest URL/ref.
The Ralf Thenable and Framer spring questions remain unresolved; the current
[remaining-work map](../../../planning/ENGINEERING_REMAINDER.md) names the required
follow-up. All six strict failures and final native/signed-artifact gates remain.
No source-only object, website, binary release, signing or notarization is published
or executed by this work. No independent legal clearance is claimed.

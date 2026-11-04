# Graphviz link-stage archive and object evidence

Two hosted builds capture the actual wasm-ld map and archive extraction reasons
while producing the same complete 1,173,021-byte backend as the published npm
input, SHA-256 `d2d18f488ffbf12fd3ae68d3899d6911051b9bfc3b4240eebe9883ca17d58903`.
This supplies concrete linker inputs for the independent compiler/runtime review.

The [captured receipt](result.json) is from
[run41850608058](https://github.com/Joncallim/mostlytext/actions/runs/41850608058),
source `c367af8b8bf9a8e19e86dc9874f4abbcb53434f9`. The earlier
[run41850441841](https://github.com/Joncallim/mostlytext/actions/runs/41850441841),
source `6653ed2e`, also passes. Every stable map/extracted archive-member identity
agrees between the two runs. Raw diagnostic hashes differ because compiler
temporary paths differ; original bytes are retained and never normalized into
equality. Both runs' ZIPs, image inspection and complete logs are retained at
`/Volumes/Fast SSD/CORTANA-Builds/graphviz-link-inputs-20261104`.

## What the files establish

- [backend.map](backend.map): 9,874 rows after its header, referencing 426 distinct
  archive/member pairs across 17 archives at the wasm-ld output stage.
- [why-extract.tsv](why-extract.tsv): all 577 reason rows, naming 457 distinct
  extracted archive/member pairs; no unparsed extracted inputs in this capture.
- The map has 32 member pairs without an extraction row, while extraction names
  63 without a map record. These sets are preserved separately; they are not
  silently reconciled or treated as equivalent retention claims.

| Archive family in the map | Distinct mapped members |
|---|---:|
| Graphviz's eight archives plus Expat | 204 |
| libc/libc_optz | 184 |
| compiler-rt | 16 |
| libc++-noexcept | 10 |
| libc++abi-noexcept | 8 |
| dlmalloc/noexit/stubs | 4 |

The complete path/member lists and every extraction reference/symbol are in the
receipt. A library name identifies an input archive; it does not independently
decide a per-file licence. These diagnostics describe **wasm-ld before subsequent
Emscripten/Binaryen processing**. They do not prove every extracted or mapped
member survives final optimization, establish a unique original historical build
or complete the independent corresponding-source/rights review. In particular,
the concrete libc++/libc++abi inputs warrant their own source/text reconciliation;
the earlier compiler-rt/root notices are not relabelled as exhaustive coverage.

## Build and trust boundary

The source/image and original five-file preparation remain those of the
[byte-identical backend reproduction](../graphviz-backend-reproduction/README.md).
A separate context adds exactly one emcc argument:
`-Wl,-Map=/output/backend.map,--why-extract=/output/why-extract.tsv`.
Removing it restores the original recipe byte for byte. Every compiler,
optimization, library order, export, working directory and runtime flag remains.
LLVM's [WebAssembly option definitions](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.6/lld/wasm/Options.td)
and [map-format regression](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.6/lld/test/wasm/map-file.s)
are format references; no SDK LLVM version is inferred from those links.

Only ephemeral hosted Linux executes the build. RUN network and shared cache are
disabled; the checkout is read-only with no persisted credential. No owner data,
secret/SSH forwarding or build-container host mounts are provided. A 45-minute
limit applies. The comparator reads bounded regular files and never loads the
generated JS/WASM. Artifacts contain public text diagnostics/JSON/logs only; no
runtime binary, source-review archive or app is published. Raw sidecars are
preserved before format parsing so a failed parse retains its actual evidence.

## Offline verification and replay

```sh
python3 compliance/tools/verify_graphviz_link.py
python3 -m unittest compliance.tests.test_graphviz_link -v
```

The verifier checks the receipt byte pin, exact raw sidecar hashes, all current
source/image/recipe/tool/output bindings and a complete recomputation of the index.
Controls reject changed/malformed/oversized data, lost reason rows, false equality,
recipe substitutions, altered stage/scope/hosted identities and rights claims.
Unknown extraction inputs remain visible instead of being silently discarded.

To prepare retained public inputs into new owned scratch without execution:

```sh
python3 compliance/tools/capture_graphviz_link.py prepare \
  --inputs /path/to/graphviz-inputs --output /path/to/new-owned-preparation
```

The explicit `--download` option captures the four pinned archives. After merge,
`gh workflow run graphviz-link-inputs.yml --repo Joncallim/mostlytext --ref main`
starts the hosted diagnostic replay. Unsupported flags or any changed complete
backend bytes fail; no build/source patches or output normalization are allowed.

Product, inventory, notice/SBOM, pins, source-offer states, original proof bytes
and release predicates remain unchanged. Independent per-file/grant and complete
source approval, separately authorized source publication/anonymous retrieval,
native and exact signed-artifact acceptance remain open in the owning issues.

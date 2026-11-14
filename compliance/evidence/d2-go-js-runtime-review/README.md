# D2 JavaScript/WASM runtime comparison

The pinned D2 source archive contains `d2js/js/wasm/wasm_exec.js` (19,885 bytes, SHA-256 `42c92bf26a564050862e648642f9dc529673fb257d8d96139122da317ac46274`). The official Go 1.24.6 Darwin toolchain archive contains `go/lib/wasm/wasm_exec.js` (16,992 bytes, SHA-256 `0c949f4996f9a89698e4b5c586de32249c3b69b7baadb64d220073cc04acba14`). D2's file carries the Go Authors BSD header. The complete Go root notice is distributed separately.

`compare-go-runtime.js` parses both with Acorn 8.14.0 and removes location/raw fields. The only AST difference is one noncomputed object key written as `debug` in D2 and `"debug"` in Go. Normalizing that key's spelling produces identical ASTs, SHA-256 `85b7d5cb8a3260783367550427f1f196878349ea1869a4a6eeaf7411f27179ea`. This establishes concrete structural correspondence to Go 1.24.6 despite formatting differences. It does not prove the historical copying event, which Go checkout D2 used, identical runtime behavior in all environments, or full source-offer completeness.

To reproduce from the locally staged D2 package, extract `original-review/upstream/d2-source-581c9109.tar.gz` and `build-inputs/go1.24.6.darwin-arm64.tar.gz`. `extract_inputs.py` verifies their complete SHA-256 values `91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391` and `4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a`, then extracts exactly these members into an empty owned directory:

```
d2-581c91096b62d644fb5168313142c836b7e68e74/d2js/js/wasm/wasm_exec.js -> d2-wasm_exec.js
go/lib/wasm/wasm_exec.js -> go1.24.6-wasm_exec.js
```

From this review directory, run:

```sh
python3 extract_inputs.py --d2-source /path/to/d2-source-581c9109.tar.gz \
  --go-toolchain /path/to/go1.24.6.darwin-arm64.tar.gz --output /path/to/empty-owned-directory
npm ci --prefix js-tokenizer --ignore-scripts --no-audit --no-fund
node compare-go-runtime.js /path/to/empty-owned-directory > /path/to/owned-report.json
cmp /path/to/owned-report.json go-runtime-ast-report.json
```

Acorn's package lock records its exact tarball URL and integrity. The parser package is a review tool, not a retained app runtime. Do not execute the extracted Go or D2 script during this comparison.

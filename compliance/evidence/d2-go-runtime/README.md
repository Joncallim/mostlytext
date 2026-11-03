# D2 Go runtime attribution — 4 November 2026

The complete [Go 1.24.6 root license](../../licenses/d2--GO-RUNTIME-LICENSE.txt)
is now included in the inventory, generated notices and SBOM. It was absent from
the previous 149-component corpus. This is a conservative attribution correction,
not independent IP clearance or completion of LC-03.

## Exact inputs and binary evidence

The unchanged publisher d2.wasm has SHA-256
`7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af`.
The [existing npm/source audit](../d2-0.1.33/README.md) binds both publisher WASM
copies, the integrity-checked npm archive and the shipped browser bundle. This
tranche does not execute WASM, rebuild a publisher binary, or change that chain.

The official [Go archive](https://go.dev/dl/go1.24.6.darwin-arm64.tar.gz) has SHA-256
`4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a`,
previously verified against the official download manifest. The archive's VERSION
identifies go1.24.6; its complete go/LICENSE is byte-identical to the captured text,
SHA-256 `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad`.
The [tagged upstream text](https://github.com/golang/go/blob/go1.24.6/LICENSE)
provides an independently inspectable reference. No generic license was substituted.

Names/strings alone are insufficient. [The deterministic audit](../../tools/audit_d2_go_runtime.py)
reads the real module's import/function/code/element/data sections, reconstructs
bounded initialized memory, validates the Go PC table, and resolves selected
runtime function records through the WASM element table to actual defined code.
The element-table step matters because wasm-opt may reorder function indices.
The Go linker documents this mapping in go/src/cmd/link/internal/wasm/asm.go
(writeElementSec/assignAddress); the PC header is in go/src/runtime/symtab.go and
function records in go/src/runtime/runtime2.go. These are present in the verified
archive. [binary-audit.json](binary-audit.json) records body lengths/digests for
runtime.main, runtime.mallocgc and syscall/js.valueCall, 7,594 Go function records,
7,752 defined WASM bodies, and the go1.24.6 marker in initialized data.

## Reproduce and scope

Use the retained immutable inputs under
`/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/`:

```sh
python3 compliance/tools/audit_d2_go_runtime.py \
  --wasm "$INPUTS/d2.wasm" \
  --go-archive "$INPUTS/go1.24.6.darwin-arm64.tar.gz" \
  --notice compliance/licenses/d2--GO-RUNTIME-LICENSE.txt \
  --output /tmp/d2-go-runtime.json
cmp compliance/evidence/d2-go-runtime/binary-audit.json /tmp/d2-go-runtime.json
```

The parser is intentionally bounded to this frozen module's section profile; it is
not a general WASM validator. Tests cover reordered code indices, names without
valid code linkage, inconsistent PC records, changed versions, missing code,
section truncation/duplicates, overlapping memory and exact archive/notice binding.
This root notice is not an exhaustive audit of every retained Go/per-file/vendor
copyright or a unique source-reproduction proof. Existing nested, font/RFN,
source-offer/publication, native notice-window and final signed-artifact gates
remain unchanged. No package pin, JS/WASM/font byte or release authority changes.

## Observed verification

All 208 compliance tests pass, including ten runtime-attribution methods. The
ordinary tree and actual compiled Release artifact checks pass. The strict release
check continues to report six existing source/rights/publication blockers.
The locked compile-only universal Release app build succeeds. Its shipped corpus
is 468,154 bytes; the unchanged Foundation-only production notice reader loads it
under its existing 2 MiB limit and finds all 99 added build/runtime credits, the
complete Go text, FreeType acknowledgment and Bison exception. Loading these
resources does not launch the app or establish native notice-window acceptance.

The refreshed Graphviz review archive has SHA-256
`165316d0ed75e8ec5beb4cf9569c900d7421a2454d19e4f5130e3637efacd240`,
25 manifested files plus its manifest, and passes exact member/byte verification.
The older archive is preserved. D2's separate earlier review archive contains its
own D2 notice, not the generated global corpus; it is not relabeled as updated.
Raw inputs, failures, controls, compile log and resource-reader evidence are in
`/Volumes/Fast SSD/CORTANA-Builds/d2-go-runtime-20261104/`. The initial invalid
generation invocation and a suite started before regeneration are retained; the
qualified results use the supported notices/sbom commands and regenerated corpus.

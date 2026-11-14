# D2 Liberation Mono replacement — controlled source build

This is a new, narrowly modified D2 build. It is not a byte reproduction of
the publisher's WASM, its optimizer, or the historical Chroma font. The old
resource and its 15/18-table comparison remain in the earlier evidence.

The input is the official Liberation Mono 2.00.5 regular TTF from the
[publisher release](https://github.com/liberationfonts/liberation-fonts/releases/tag/2.00.5),
archive SHA-256 `f14ff0a0be87b5aeb672e669363b5a699db76feb1144b06798261c0fdcd2b24d`,
TTF SHA-256 `816a2a46416a2d3550b401ff8d0c084ba7e8138782f7057b1e537446012f769a`.
The repository's `convert_lossless_woff.py` uses Python 3.15.0 stdlib zlib
1.2.12 level 9 to wrap its unchanged sfnt tables as WOFF1, with no WOFF
metadata or private block. `font-conversion.json` records all 18 original and
decoded table lengths, checksums and hashes. The resulting 174,936-byte WOFF
is `5b995acac71be5c793f11417f57f1af41bd7ff312248eb13ea04b6cf15311a71`.
The name table, `post` table and underline/fixed-pitch fields are unchanged
from that TTF. This is a format conversion, not a glyph or metadata edit.

The WOFF replaces only the base64 font in Chroma v2.14.0's
`formatters/svg/font_liberation_mono.go`; the source patch is
`chroma-liberation-mono.patch` (SHA-256
`5c37b1b89796e190aa07ebe96642bf1b0d0743291d96e41ad7328b1c70285f7e`).
Pinned D2 source is commit `581c91096b62d644fb5168313142c836b7e68e74`.
The controlled build uses Go 1.24.6, the previously verified 16 module ZIPs,
offline module resolution, `GOOS=js`, `GOARCH=wasm`, `CGO_ENABLED=0`,
`-mod=readonly`, `-trimpath`, `-s -w`, a relative
`../chroma-v2.14.0` Go module replacement, and two explicit linker values:
`d2js/d2wasm.jsVersion=0.1.33` and
`lib/version.Version=v0.6.10-0.20250817190149-581c91096b62+dirty`.
The latter preserves the publisher's recorded render metadata; it does not
assert that this source tree has the publisher's Git state. The new 23,704,068
byte WASM is SHA-256
`175e672a9a6c939a65363c50e4092c7c217add5f9a0fb91364e906a9b137586e`.
It contains the new font literal once and the prior literal zero times.

An independent clean module-cache replay uses
`seed_d2_module_proxy.py` on the local source-review archive to create a
`file://` GOPROXY containing those 16 verified ZIPs, module files and version
records. With `GOMODCACHE` pointing at an empty directory and
`GOTOOLCHAIN=local GOPROXY=file://… GOSUMDB=off GOENV=off GOWORK=off`, the
same patched source and Go 1.24.6 produce the exact WASM SHA above, with no
remote module fetch. This verifies dependency replay for the controlled new
build; it does not reproduce the historical publisher optimizer or establish
the missing ELK/decoder/Go runtime rights and source mapping.
An initial full replay used an absolute local Chroma replacement path. Go
embedded that path in WASM build metadata, causing a different digest and a
private machine path. The accepted build and clean replay both use the
relative sibling directory shown above; their entire WASM files match, and
neither contains an absolute user-home or mounted-volume path.

The local review archive includes the input archives and proxy seeder. In a
new disposable work directory, unpack the archive, then extract
`build-inputs/go1.24.6.darwin-arm64.tar.gz`,
`original-review/upstream/d2-source-581c9109.tar.gz`, and
`original-review/modules/02/source.zip`. Apply
`patches/chroma-liberation-mono.patch` with `patch -p1` from the extracted
`github.com/alecthomas/chroma/v2@v2.14.0` directory. Place the patched Chroma
directory beside the extracted D2 source as `chroma-v2.14.0`, name the D2
directory `d2-source`, and from it run
`go mod edit -replace=github.com/alecthomas/chroma/v2=../chroma-v2.14.0`.
Seed a fresh local proxy with:

```sh
python3 build/seed_d2_module_proxy.py --archive <review-archive.tar.gz> \
  --output <empty-proxy-directory>
```

Set `GOPROXY` to that directory's absolute `file://` URI (encode spaces),
`GOMODCACHE` to an empty directory, `GOENV=off GOSUMDB=off GOTOOLCHAIN=local
GOWORK=off CGO_ENABLED=0 GOOS=js GOARCH=wasm`, and use the extracted Go 1.24.6
binary for `go build -mod=readonly -trimpath ./d2js` with
`-ldflags='-s -w -X oss.terrastruct.com/d2/d2js/d2wasm.jsVersion=0.1.33 -X oss.terrastruct.com/d2/lib/version.Version=v0.6.10-0.20250817190149-581c91096b62+dirty'`.
Compare the output SHA with the value above. The scripted seeder plus a clean
module cache produced the same digest in the recorded replay.

`replace_d2_wasm_payload.py` admits only the verified publisher browser bundle
and its verified old Brotli WASM literal, then replaces that literal alone. It
uses Node v26.11.1 Brotli and verifies decompression. The report pins the
resulting browser resource described below.
The new compressed payload is 5,466,981 bytes, below the publisher's
5,495,873 bytes. The complete new browser resource is 8,156,339 bytes,
SHA-256 `ef6d450712e4356ccdd5e9e3a732c4b9a761ac69ab7a71407012ad36dcf49fd0`.
That is 38,524 bytes smaller than the reviewed 8,194,863-byte publisher
browser export. The unoptimized WASM itself is 1,631,284 bytes larger than
the publisher's optimized 22,072,784-byte WASM. The compressed bundle shrank,
but the larger raw WASM may affect decompression, compilation, memory and
startup. The selected local renderer timings do not constitute a controlled
cold performance benchmark.
The historical
Binaryen comparison timed out without output and is not silently retried.

The repository notice describes the two bundle modifications. The local
D2 source-review archive preserves original source/build receipts and this
new patch and conversion, but its nested ELK, decoder and per-file review is
not yet complete or approved for publication. [OFL webfont guidance](https://openfontlicense.org/webfonts-and-reserved-font-names/)
allows unchanged table data to retain Reserved Font Names in some format
conversions; the final case-specific RFN judgement remains for independent
rights review. A technical table comparison is not a legal opinion.

The final relative-path resource passes 36/36 selected package tests across
the D2 renderer, real SVG namespace, preview/export source parity and SVG
resource-admission suites. The 14 focused renderer tests include code
highlighting, invalid syntax, pooled-page recovery, concurrency,
size/timeout guards and colour modes. These local tests do not establish visual font metrics or
underline behavior in the installed app, nor signed-app/native acceptance. The exact signed app and final
published source location remain release prerequisites.

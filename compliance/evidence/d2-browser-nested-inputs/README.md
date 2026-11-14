# D2 browser payload nested-source audit

`reproduction.json` records the original shipped browser resource
`991a44779c91b74cbdf141228a6ba34592fe9b708fe19c221eba9ef4a7cfe33e`.
The new font build changes only its compressed WASM literal, so these JavaScript
inputs are unchanged. The original bundle's embedded compressed ELK payload
decompresses byte for byte to the pinned D2 source's
`d2layouts/d2elklayout/elk.js` (`a297b92da4a257b95c129cc1d8cfb379e2c89bcd4442af90ac06fdd2b1e220b4`).
D2 identifies elkjs 0.8.2. The official
[elkjs 0.8.2 source](https://github.com/kieler/elkjs/tree/0.8.2) and its
EPL-2.0 text are included in the local review package. Its generated JS does
not match the pinned D2 file byte for byte. The elkjs build also references
separate ELK Java source, GWT and `melk:0.8.1`; the candidate
[ELK Java v0.8.1 source](https://github.com/eclipse-elk/elk/tree/v0.8.1)
is retained but does not establish the exact historical generated-runtime
inputs or all per-file obligations. [D2's file history](../d2-elk-history/README.md)
now binds the pinned `elk.js` to its August 2025 Git blob and identifies the
four later D2 edit commits after the 2022 introduction. This narrows the
D2-specific modifications but does not reproduce the original generated file
from ELK Java/GWT inputs. The source offer therefore remains open.

The pinned D2 source embeds `d2js/js/vendor/decode.min.js` (SHA-256
`67de1ff9e3bf170ca99d317a6466cb107f288a1f565f3971cd7dd8dc9922f677`)
through `d2js/js/build.js`. A [pinned AST comparison](../d2-js-brotli-source/README.md)
identifies [Google Brotli commit `3efb30f`](https://github.com/google/brotli/commit/3efb30f96ba50389c4a2fcd9f884b7dbfbadebae)
as a much closer technical source reference: its `js/decode.min.js` is
150,933 bytes and has the same location-free Acorn 8.14.0 AST as D2's
167,903-byte file. The bytes differ. A deterministic snapshot of the complete
377-file Google Git tree, including all 14 JavaScript files and `LICENSE`, is
staged in the local package. Its root MIT text matches the distributed notice.
The earlier Google v1.1.0 export and deterministic Git snapshot remain as
historical evidence; the export omits `js/`, and that tag's decoder differs
from D2 even in AST. [D2's introduction commit](https://github.com/d2lang/d2/commit/114582583c7ce7885930c16cb7581370bfcd0e3e)
added it in August 2025, and [the next vendor move](https://github.com/d2lang/d2/commit/1dc42d26dad139b2ce0161177b00beee2182c8b6)
changed its path. Neither establishes the exact copied revision or generated
transformation. This technical match does not independently clear the grant
or full per-file source offer. The separately attributed Go
`andybalholm/brotli` module does not cover this JavaScript decoder.

`d2js/js/wasm/wasm_exec.js` in the pinned D2 source has SHA-256
`42c92b...`; it differs from the Go 1.24.6 source copy
`go/lib/wasm/wasm_exec.js` (`0c949f...`). The complete Go root licence and
selected standard-library notices are already distributed. The
[pinned AST comparison](../d2-go-js-runtime-review/README.md) extracts both
files from their complete source archives and finds only a noncomputed `debug`
object key spelling difference in Acorn 8.14.0's location-free AST. After
normalizing that key, the ASTs are equal. This narrows technical correspondence
to Go 1.24.6; D2's historical copied revision, exact execution behavior and
complete source/runtime obligations remain review inputs. The
two shortened digests above are identification aids; the full pinned values
are in `reproduction.json` and the original D2 source archive.

The generated notice and inventory now name the ELK, JavaScript Brotli and Go
runtime components separately. No whole D2 binary or JavaScript emitter
reproduction follows merely from matching these nested source fragments.

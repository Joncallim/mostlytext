# D2 browser resource split

The reviewed current-main input at `2f349bd6` is
`MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js`,
SHA-256 `ef6d450712e4356ccdd5e9e3a732c4b9a761ac69ab7a71407012ad36dcf49fd0`.
The embedded Brotli payload decompresses to 23,704,068 bytes of WebAssembly,
SHA-256 `175e672a9a6c939a65363c50e4092c7c217add5f9a0fb91364e906a9b137586e`.
The latter is the exact controlled font-replacement build recorded in
`compliance/evidence/d2-font-replacement/`.

`repack_d2_browser.mjs` verifies both input and payload digests, removes only
the compressed literal, and changes the loader to fetch the adjacent resource.
It produces `d2-browser.js` (867,047 bytes, SHA-256
`10d9bd5f664ee131783df6c39fc864452758ba8b7e39e05998fec81658426a1c`)
and `d2.wasm` (23,704,068 bytes, digest above). Reproduce using Node's built-in
Brotli decoder:

```sh
git show 2f349bd6:MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js > /tmp/mostlytext-reviewed-d2.js
node compliance/evidence/d2-runtime-resource/repack_d2_browser.mjs \
  /tmp/mostlytext-reviewed-d2.js /tmp/mostlytext-split-d2.js /tmp/mostlytext-d2.wasm
shasum -a 256 /tmp/mostlytext-split-d2.js /tmp/mostlytext-d2.wasm
```

The WebKit page and its four exact D2 resources use a private bundled URL
scheme. This is a packaging change, not a new D2 build, a reproduction of the
publisher optimizer, or completion of the source offer and rights review in
issue #14. The original compressed resource remains in Git history.

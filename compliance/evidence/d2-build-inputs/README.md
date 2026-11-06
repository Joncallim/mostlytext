# D2 build-input investigation — 7 November 2026

The source archive and npm package are unchanged. A bounded offline build now
matches the publisher's complete Go build-ID string and recorded main-module
version. It **does not reproduce the complete publisher WebAssembly file**.
The declared optimizer comparison times out without an output. This packet
records additional actual source/build inputs and these limits; it clears no
licensing, font, corresponding-source publication or release gate.

## Verified inputs

- Publisher module SHA-256: `7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af`.
- Source commit: `581c91096b62d644fb5168313142c836b7e68e74`; archive
  `91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391`.
  All 2,895 tracked regular source files match their archive bytes.
- Official Go 1.24.6 Darwin/arm64 archive:
  `4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a`.
  All 14,175 extracted regular compiler/source files match the archive.
- All 16 selected external-module ZIPs match the recorded Go Hash1/h1 sums;
  every selected expanded file and complete file set matches its verified ZIP.
  The failed broad offline `go mod verify` log is retained: it requested an
  uncached native-only module outside this target graph. Network resolution and
  automatic compiler selection remained disabled for the actual target builds.

The complete input maps and actual compiler commands/status/full logs are
retained here, with large text records gzip-compressed. Only standalone
compiler tools ran locally; the module, product app, publisher scripts, fonts
and native rendering helpers were never executed.

## Missing source-reference inputs identified

The original source archive omitted Git version ancestry. A no-tag checkout
records `v0.0.0-20250817190149-581c91096b62+dirty`, while the publisher records
`v0.6.10-0.20250817190149-581c91096b62+dirty`. A genuine history fetch also
followed newer tags and produced a second, rejected version observation; its
full output/log is retained, without inventing an accepted child status.

A separate reference checkout preserves exactly the real source commit and
actual `v0.6.9` tag object `4b0b7da6fd26c052ac4104ae5ab952d8a50fff89`, peeled
ancestor `17399682f8289ac6999fe2e6fbb3f738ddb264ce`. No captured original ref is
removed. This declared reference view, the frozen compiler/modules and only
an explicitly recorded untracked audit marker for the actual dirty flag produce
the recorded main-module version and full Go build ID. It is one view consistent
with those fields, **not an attestation of the publisher's full Git refs or dirty
working tree**. All tracked source bytes remain unchanged. The normal target
compile takes 7.472 seconds and produces 23,704,208 bytes, SHA-256
`150faf74fe50b9390b71c5f728ade89416db4a18b1873a1b98d2b49084aa5049`.
Complete-file and initialized-memory comparisons still differ. Matching build
IDs or source names do not substitute for complete binary correspondence.

The root source also declares build-helper submodule `ci/sub` at
`2594100ac939644f134e24edac7c9bcd569b99f6` from
[terrastruct/ci](https://github.com/terrastruct/ci/tree/2594100ac939644f134e24edac7c9bcd569b99f6).
Its complete 37 tracked files, including the original ISC-style permission and
copyright text, are retained in `terrastruct-ci-2594100a-source.tar.gz`. The
complete manifest is `verified-source-submodule.json`; these files were only
read. The older source-review archives remain unchanged and must not be called
complete merely because this supplemental helper archive now exists.

## Optimizer comparison and first failure

The immutable upstream script optionally runs `wasm-opt -Oz
--enable-bulk-memory-opt`; its workflow installs unversioned distribution
Binaryen. The publisher's actual optimizer version is not established.

One declared comparison uses the official
[Binaryen version_123 release](https://github.com/WebAssembly/binaryen/releases/tag/version_123),
whose ARM macOS archive matches its adjacent official SHA-256
`74428be348c1a09863e7b642a1fa948cabf8ec9561052233d8288e941951725b`.
The executable/library bytes and complete extraction map are recorded. Both
link only compiler/system libraries, without GUI/font/drawing frameworks.
With one compiler worker and the reviewed flags, the owned comparison reaches
its unchanged 300-second bound (300.969 seconds observed), is terminated, and
produces **no output**. Full status and stdout/stderr are retained. No unchanged
retry, higher limit, alternate version search or metadata editing was performed.

No unique original optimizer or complete reproducible WASM/JavaScript build is
claimed. No shipped JS/WASM/font, package pin, generated notice, source-offer
status or strict release guard changes. Font/RFN, nested/per-file rights,
complete corresponding source/build material, separately approved source-only
publication/anonymous retrieval and final signed-artifact acceptance remain open.

## Review and reproduce the observations

`manifest.json` binds every packet member. The original immutable npm/source/
Go inputs remain under the recorded local capture; owned compilation outputs
and full comparison files remain under the raw audit directory recorded by the
status files. They are not silently replaced by normalized derivatives.

Before any new build, independently verify all captured input maps, genuine
reference ancestry and exact compiler/dependency hashes. The actual status
records contain the direct offline Go compiler commands, which use
`GOTOOLCHAIN=local`, `GOPROXY=off`, `GOSUMDB=off`, `GOENV=off`, `GOWORK=off`,
`CGO_ENABLED=0`, `GOOS=js`, `GOARCH=wasm`, `-mod=readonly`, `-trimpath`, and the
recorded `jsVersion=0.1.33` linker setting. The declared audit marker alone
accounts for the recorded dirty flag. The unmodified upstream `build.sh`
publishes to npm: **do not execute it to reproduce this audit**.

The failed optimizer comparison is evidence, not a command to retry unchanged.
Further optimization work needs an explicit new immutable-input or architectural
decision. Preserve all first failures. Ordinary Compliance performs no Go,
optimizer, WASM, publisher, app or native-helper execution for this packet.

Observed repository verification: all330 compliance tests and the ordinary
inventory check pass. Every supplemental helper archive member matches its
actual frozen Git object; complete packet member digests are checked. The
first packet verifier refused an incorrectly assumed licence phrase (`and/or`);
its refusal is retained and the verifier was corrected to the actual original
`and` wording. No licence or source byte was changed.

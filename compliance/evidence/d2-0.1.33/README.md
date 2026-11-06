# D2 browser source and Go-module audit (#148 LC-03)

> Further font evidence — 3 November 2026: [the exact table comparison](../d2-font-reference/README.md)
> relates the embedded Version 2.00.5 WOFF to the font project's published TTF.
> Fifteen of 18 tables are identical; post-table underline/fixed-pitch metadata
> differs. This narrows the review and prevents an unsupported unchanged-font
> claim. It does not resolve RFN/functional-equivalence or original conversion
> provenance, change the selected font/binary, or clear the D2 release item.


> Current module notice update — 3 November 2026: complete root texts for all 16
> recorded module inputs are now distributed as conservative publisher source-build
> attributions, including FreeType's complete selected FTL option and binary credit.
> [The checkpoint](../nested-build-attribution/README.md) records exact sources and
> the lossless legacy-encoding conversion. Earlier statements that those root texts
> are absent are historical. Independent WASM/source/nested review, Liberation Mono
> RFN treatment, approval/publication and exact-artifact acceptance remain open.

> Build-input investigation — 7 November 2026: [the supplemental packet](../d2-build-inputs/README.md) records genuine version-tag ancestry and the exact 37-file build-helper submodule omitted by the source archive. The offline target matches the recorded module version/full Go build ID, but complete files still differ and the declared optimizer comparison times out without output. No source/rights/publication gate is cleared.

## Owner summary

The shipped D2 browser bundle is now tied byte-for-byte to the official npm
package and its one local export replacement. The publisher's npm metadata
names an immutable upstream source commit. Querying that commit's documented
Go-to-WebAssembly target reaches 16 external Go modules, each with an exact
version, Go checksum and captured root licence-text hash in
[`source-graph.json`](source-graph.json). This is useful source-availability and
attribution preparation, not a completed release gate: the package publisher's
binary was not independently rebuilt, nested/embedded texts have not been
fully reviewed, a local source-review bundle has been prepared but not approved
as the complete corresponding-source offer or published,
and the final app has not been checked. No inventory `open_items` or
`source_offer.status` is changed.

## Inputs and findings

Official [npm metadata](https://registry.npmjs.org/@terrastruct%2fd2/0.1.33)
reports `@terrastruct/d2@0.1.33`, repository directory `d2js/js`, and
`gitHead` [`581c91096b62d644fb5168313142c836b7e68e74`](https://github.com/d2lang/d2/commit/581c91096b62d644fb5168313142c836b7e68e74).
The [npm archive](https://registry.npmjs.org/@terrastruct/d2/-/d2-0.1.33.tgz)
matches the registry's SHA-512 integrity value. Its SHA-256 is
`b84f8fe9b8d4e32223a436a54aa47867179856612174e803c04a725c93834191`.
The upstream `dist/browser/index.js` SHA-256 is
`9898965444a940cdbedda3b039f717e96a86ffe9b3170bf30f8fea94ffb66e8a`.
The shipped file SHA-256 is
`991a44779c91b74cbdf141228a6ba34592fe9b708fe19c221eba9ef4a7cfe33e`.
The exact change is one replacement after a shared 8,194,848-byte prefix:
`export{lw as D2}` becomes `window.D2=lw;`; the final two bytes are shared.

The [source archive at that commit](https://github.com/d2lang/d2/archive/581c91096b62d644fb5168313142c836b7e68e74.tar.gz)
has SHA-256 `91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391`.
Its `d2js/js/ci/build.sh` invokes `GOOS=js GOARCH=wasm go build` on
`./d2js` with Go 1.24.6. The source checkout's `package.json` says 0.1.32;
the same release script sets the npm publication version to 0.1.33. The
published npm archive contains two identical `d2.wasm` copies (SHA-256
`7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af`).
The shipped browser bundle is the verified npm output, but this audit has not
reproduced its JavaScript or WebAssembly build.

With a checksum-verified, temporary official Go 1.24.6 toolchain and the
source archive extracted locally, `GOOS=js GOARCH=wasm go list -deps -json
./d2js` completed with no package errors: 288 packages and 16 external modules.
The manifest records each selected module's version, Go sum, source-package
count and root licence-text filename/hash. The FreeType module's licence is a
dual-choice text; its distribution choice and any nested code/NOTICE duties
require review before these texts are installed into shipped notices. The
source graph is not proof that the npm publisher built exactly these bytes
from this commit; npm `gitHead` is publisher provenance, not a rebuild attestation.

## Reproduction and controls

Raw npm metadata, integrity-checked npm archive, source archive, the extracted
WebAssembly, Go download manifest/toolchain, Go package graph and stderr are
retained under
`/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/`.
The temporary Go archive's SHA-256
`4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a`
matches the official [Go download manifest](https://go.dev/dl/?mode=json&include=all).
No system Go installation or website change was made.

From the repository root, with those inputs available:

```sh
python3 compliance/tools/audit_d2_source.py \
  --metadata /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/npm-metadata.json \
  --npm /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2-0.1.33.tgz \
  --source /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2-source-581c9109.tar.gz \
  --go-list /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2js-wasm-go-list.json \
  --shipped MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js \
  --output /tmp/d2-source-graph.json
cmp compliance/evidence/d2-0.1.33/source-graph.json /tmp/d2-source-graph.json
```

The Go graph was generated in the extracted source root with:

```sh
env GOOS=js GOARCH=wasm GOTOOLCHAIN=local \
  GOMODCACHE=/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/gomodcache \
  GOCACHE=/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/gocache \
  /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/go/bin/go list -deps -json ./d2js
```

The audit rejects an npm tarball that violates registry integrity, a shipped
bundle changed beyond the exact export replacement, and a Go graph with an
incomplete package. Its negative-control results are retained with the raw
inputs (`negative-controls.log`): all three controls failed as intended.
`python3 -m py_compile compliance/tools/audit_d2_source.py`,
`python3 compliance/tools/compliance.py check`, and `git diff --check` passed.
The existing compliance suite passed 82 tests under the authorized executor.
Its first default-sandbox launch failed 10 release-script fixtures before their
assertions because Bash could not open `/dev/fd/62`; both logs are retained.
The ordinary tree compliance check remains green; the strict release check
still has the same seven pre-existing findings.

## Remaining LC-03 work

Review module and nested-code licence obligations, include the required
texts in the inventory and generated notices, promote the local review bundle
to a complete immutable source package, and obtain independent provenance review.
Source-only public publication and anonymous retrieval belong to the later
owner-authorized LC-09 phase. Keep #148 open until preflight and final
exact-artifact criteria are met.

## Local source-review bundle verification — 20 October 2026

The previously prepared local bundle at
`/Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2-source-review-bundle.tar.gz`
has SHA-256 `07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02`.
It contains the publisher npm archive, the publisher-reported upstream source
archive, the one-line browser export patch, 16 versioned Go module source ZIPs,
their captured root licence files, D2's licence and notice, and a 37-file
manifest. The reviewed manifest is copied verbatim to
[`offer-manifest.json`](offer-manifest.json), SHA-256
`fc5b58190024eb529cf76394b6b2b23c4208348ace64a2c2ad07120cabfbdec3`.
The 16 module ZIPs also matched the preserved Go module cache byte-for-byte;
each cache `.ziphash` matched its recorded `go_sum`.

Run from the repository root:

```sh
python3 compliance/tools/verify_d2_offer.py \
  /Users/jonathanlim/GitHub/_cleanup-archive/d2-source-148-2026-10-20/d2-source-review-bundle.tar.gz
python3 -m unittest compliance.tests.test_d2_offer
```

The verifier passed: it rejects unsafe or duplicate archive members, checks
the archive's exact member set and bytes against the committed manifest, ties
the npm and upstream archives to the source graph, checks that the documented
export replacement reproduces the shipped browser bytes, applies the archived
one-hunk patch to the published file, and compares all 16 module identities,
ZIP paths, and root licence texts to the source graph. Five negative controls
passed (duplicate member, traversal path, changed reviewed manifest, corrupt
member hash, and a patch that does not reproduce the shipped file). This proves
local package consistency, not that the published WebAssembly was independently
rebuilt from the reported sources.
The full compliance suite passed 86 tests; `compliance.py check` and
`git diff --check` passed. The first full-suite launch in the restricted
sandbox failed ten release-script cases before their assertions because Bash
could not open `/dev/fd/62`; the unchanged suite then passed outside that
nested sandbox. Its log is `/tmp/mostlytext-d2-offer-full-tests.log`, SHA-256
`f7f05b65c4be5383c6ded2381b7653d8f9c91651aff853652d271da7b333ef4e`.

The FreeType-Go module offers a FreeType License or GPL choice; its separate
test-data font licence is present in the source ZIP but the test data is not
identified as a compiled package by the recorded Go graph. The distribution
choice and any additional embedded-code notice duties still need independent
review before adding shipped notice texts or calling this a complete offer.
In particular, the pinned Chroma v2.14.0 SVG formatter embeds a Liberation
Mono WOFF font. The `formatters/svg/font_liberation_mono.go` file in the retained
module ZIP has SHA-256 `62b52a13f5eaa92c7ec5cecbdb9fc17871ad98095668967938ffe3ae4ee96a2c`.
Its 233,248-byte base64 WOFF string has SHA-256
`08a76705aa3a34ece73a65398252e0df807f7671231a0d2a3f6fd4719e851380`
and occurs exactly once at byte offset 14,657,061 in each byte-identical
publisher `d2.wasm` variant (SHA-256
`7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af`).
The decoded 174,936-byte WOFF has SHA-256
`29d9447a83dbf9866aff37f7dc972441302da97f9a242ea0405f60841e9b630f`.
Its `name` table identifies the family as Liberation Mono, names Google and
Red Hat in its copyright metadata, and identifies SIL OFL 1.1. The exact
copyright, Reserved Font Name declarations and OFL text from the Chroma source
header are now carried as the separate `d2-liberation-mono` embedded component
in the generated third-party notices and SBOM. The source header stripped of
Go comment markers is copied at `compliance/licenses/d2--LIBERATION-MONO-OFL.txt`
(SHA-256 `985e76906c34ca203039d0d0aa47237d059de14d7c70c891e7f75171d0258753`).
See [the pinned font source](https://github.com/alecthomas/chroma/blob/v2.14.0/formatters/svg/font_liberation_mono.go)
and [formatter registration](https://github.com/alecthomas/chroma/blob/v2.14.0/formatters/api.go).
This is publisher-byte correspondence and attribution, not an independent
WebAssembly rebuild. The font's Reserved Font Name treatment still requires
review under the D2 LC-03 release finding; this change does not clear it or
publish the source archive. The [OFL guidance on webfonts and Reserved Font
Names](https://openfontlicense.org/webfonts-and-reserved-font-names) explains
why format conversion and embedding need a case-specific review. The WOFF name
table retains `Liberation Mono`; no MostlyText-side font conversion or edit was
made. Reproduce the byte and notice checks with:

```sh
python3 compliance/tools/verify_d2_offer.py /path/to/d2-source-review-bundle.tar.gz
python3 compliance/tools/verify_d2_font.py --archive /path/to/d2-source-review-bundle.tar.gz
python3 compliance/tools/compliance.py check
```

The verifier accepts only the retained archive SHA-256 above. With that archive
it reported the source, encoded/decoded font, publisher WASM and copied licence
hashes above. A copy of the licence with one added line was rejected. All 87
compliance tests passed outside the nested sandbox; `check --release` still has
seven findings, including the unchanged D2 public-source URL and the expanded
LC-03 review item. These checks do not establish font-version identity or legal
clearance of the publisher's Reserved Font Name use.
The archive is local only. `source_offer.status` remains `planned`, the strict
release check retains its D2 findings, and no website object or binary was
published.

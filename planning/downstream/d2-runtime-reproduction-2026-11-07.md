# Reproduce the captured D2 WebAssembly inputs without changing the renderer

## Owner summary

Strengthen the remaining D2 corresponding-source evidence by rebuilding its
captured Go-to-WebAssembly target and comparing real output to the unchanged
shipped publisher module. This is source/provenance work, not a font remedy,
independent rights clearance, public source offer or native renderer acceptance.
No shipped JavaScript/WASM, font, dependency or release guard changes.

## Baseline and readiness

Main remains d607098b. Pending integration0557e08f preserves the reviewed product
inputs; this separate E14 source-only branch starts there and may proceed from
its stable exact interfaces while all integration checks run. Read AGENTS,
EPIC_STANDARD, RELEASE_HARDENING, ARCHIVE_PLAN, UPSTREAM_REVIEW_QUESTIONS,
D2 source graph, Go-runtime record and exact font comparison before execution.
The original npm package0.1.33 identifies source581c91096b62d644fb5168313142c836b7e68e74;
the source archive is91e4234ad509b7e673a19541feda2b66f88311b3c6dd9f8257a0d2e350922391.
Its captured wasm is7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af.
The original official Go1.24.6 Darwin/arm64 archive and16-module cache remain
available. Preserve their original paths/bytes; use separate owned build/cache
outputs. No product executable, native helper or GUI library runs locally.

## Pre-implementation inspection and boundaries

Inspect the immutable upstream build script as text only. It invokes the Go
wasm target with -trimpath, -s/-w and jsVersion0.1.33, then optionally wasm-opt
-Oz --enable-bulk-memory-opt and Bun bundle generation. It also publishes to npm;
NEVER execute the publisher script. Invoke only individually reviewed compile
commands with a verified compiler. No npm token, credential, upstream message,
push, publication or source-offer approval is part of this work.

First inspect the actual wasm custom sections/build info and source workflow
for recorded tool/settings, without running the module. Validate source/npm/
compiler archives by their existing complete hashes. Verify the actual Go binary
against its archive before execution. Fetch a read-only exact upstream commit
if its VCS metadata is required; compare every tracked source member to the
verified archive. A deliberately recorded untracked audit marker may represent
the module's explicit vcs.modified=true build field, but no tracked input may
be altered silently and no publisher content/state is inferred from that flag.

## Narrow build spike

Use an owned separate source/cache/output root. Disable Go network resolution
and automatic toolchain selection; freeze go.mod/go.sum and require readonly
module mode with CGO disabled and GOOSjs/GOARCHwasm. Record all actual compile
arguments, compiler/source/module inputs, complete stdout/stderr, normal/bounded
exit and output digest. A first pre-optimization build is bounded to300s; preserve
all mismatches/failures. Do not mutate shared original captures/caches.

Compare the complete wasm and, when needed, exact section/function/data/build
metadata differences. Original file hashes stay authoritative. A known optimizer
reference may only be chosen from actual primary provenance or explicitly
labelled a comparison candidate; never invent an original publisher version.
Any optimization/bundling continuation needs a written decision specifying
immutable tools and commands before execution. No repeat-until-green loop,
normalised false equality, removed section or hidden source change.

## Evidence and completion

Only byte-identical complete output establishes that reproduction result. Exact
instruction correspondence with different metadata/optimization remains narrower
comparison evidence, never a complete rebuild. Preserve the publisher's existing
provenance limit, unresolved font/RFN/nested obligations and independent review.
A successful result may update the source-only review packet, reproducible recipe
and fail-closed pure controls, with all compliance/inventory checks and a separate
documentation/evidence PR against the actual integrated main. Any source archive
or notice update requires normal corresponding manifest/hash checks. Do not
rebuild, sign, replace or publish a shipping renderer as an audit shortcut.
There is no new UI, persistence, export, locale, cancellation or resource policy.
The frozen integration candidate is not modified by this spike.

## Preparation correction: verify the selected module inputs directly

The first offline go mod verify command stops before compilation because it
attempts to resolve a native-only websocket module outside the recorded16-module
js/wasm selection. Preserve its original log. Verify each selected module ZIP
using Go's canonical Hash1 construction against the existing source-graph h1
sum, then compare every expanded module file and complete file set byte-for-byte
to that verified ZIP. This supplies an independent complete selected-input check
without broadening the dependency graph or enabling network resolution. Keep
the original go.mod/go.sum and every tracked source byte unchanged. If the
actual target build needs uncaptured metadata, preserve that first failure and
document the exact missing immutable input before any preparation change.

## First target result and missing build-helper inspection

All16 selected ZIPs match their recorded Go h1 sums, and every expanded file
plus complete file set matches its ZIP. The first offline target build exits0
in9.591s, produces23,704,208 bytes with SHA25690cbb3a1..., and preserves every
tracked source byte. It does not match the publisher's optimized module. Section
comparison retains both complete files: raw7594 functions versus publisher7752,
raw type count12 versus59, and the same explicit Go1.24.6/VCS build fields. No
complete reproduction or optimizer version is inferred.

The verified root make.sh prepends ci/sub/bin before invoking the Go build. The
source archive omits that gitlink's contents. Inspect the exact declared public
submodule https://github.com/terrastruct/ci at2594100ac939644f134e24edac7c9bcd569b99f6
as read-only source, comparing the gitlink and .gitmodules against the frozen
root commit. Do not execute its wrapper or publisher scripts. Record all input
hashes/licence, inspect any compiler flag/version transformation and write the
next precise compile/optimizer decision before execution. This may identify an
additional corresponding-source input; no shipped component or offer status is
changed from a missing-script observation.

## Recorded VCS-version input missing from the shallow source capture

Read-only linear-memory comparison identifies a concrete build-info difference:
the publisher records main module v0.6.10-0.20250817190149-581c91096b62+dirty,
whereas the initial shallow checkout has no version tags and records
v0.0.0-20250817190149-581c91096b62+dirty. Both preserve the same source commit
and explicit Go/VCS fields. The third Go build-ID component matches, while the
complete modules and memory images differ; no equality is inferred.

Capture the actual public v0.6.9 tag and sufficient genuine ancestor history to
verify it is an ancestor of the frozen source commit. Record exact tag/object
IDs and verify HEAD/all tracked source hashes remain unchanged. This supplies a
real recorded version-construction input, not an invented string or binary edit.
Only after the ancestry is established, repeat the same reviewed offline Go
compiler command with unchanged source/module/tool hashes and frozen locks, to
a separate named output. Retain the original mismatch. Require the resulting
main-module version to match the actual publisher field; if it does not, stop
and record the unresolved input. Do not patch build-info or strip metadata to
claim a complete reproduction. Optimizer continuation still requires its own
explicit immutable-tool decision.

## Freeze the reference tag view without altering captured refs

The genuine-history fetch automatically followed newer tags, includingv0.7.0,
and the next file records v0.7.1-0...+dirty instead of the publisher'sv0.6.10-0.
The observer's version assertion rejects it; its full file/log and actual
observed field are preserved. The first driver did not write its child status
before that assertion, so no accepted normal-build result is inferred from it.

Create a separate local reference checkout from the already captured real Git
objects, fetching with --no-tags only the frozen root commit and actualv0.6.9
tag/ancestry. Preserve the previous checkout and all fetched tag refs intact.
Record the complete selected reference set and all source hashes, then invoke
the same reviewed offline compiler command with the same frozen16 modules and
real compiler. This explicitly reconstructs one ref view consistent with the
recorded module-version base; it is not a claim about the publisher's full ref
set or an invented/edited build-info string. Use only the declared untracked
audit marker for the recorded dirty flag. Persist command/status/output metadata
before testing the expected version, including on refusal. Still require full
file equality for any reproduction statement; no metadata is stripped/patched.

## Bounded optimizer comparison decision

The declared two-ref source view produces the actual recorded main-module
version with a normal7.472s offline compile; all tracked source stays unchanged.
The complete23,704,208-byte preoptimizer wasmSHA256150faf74fe50b9390b71c5f728ade89416db4a18b1873a1b98d2b49084aa5049
still differs from the publisher. Preserve all three earlier observations.

Use one explicitly labelled comparison tool, official Binaryen version_123,
released2025-03-25, asset binaryen-version_123-arm64-macos.tar.gz from
https://github.com/WebAssembly/binaryen/releases/tag/version_123. Capture the
release metadata, release tag/object and official adjacent SHA256 before any
execution; verify archive checksum, safe archive paths and actual compiler
linkage. Extract only to owned audit storage; no system installation or product
execution. This tool is not claimed to be the publisher's optimizer: the
immutable upstream daily workflow installs unversioned distribution binaryen.
Its version remains an explicit missing input unless independently evidenced.

After the tool input is verified and linkage excludes GUI/font/drawing
frameworks, record wasm-opt --version then perform one bounded300s optimizer
invocation: wasm-opt -Oz --enable-bulk-memory-opt tagged-reference-d2.wasm
-o binaryen123-comparison-d2.wasm. Use a minimal compiler environment and
separate output; retain the complete raw stdout/stderr/status and both input
and output hashes. Never execute the wasm, Bun bundle or publishing scripts.
Compare complete files and exact sections/data/instructions, retaining every
mismatch. No additional optimizer version search, edited metadata, source
patch, removed custom section or repeated unchanged attempt is authorised by
this decision. A mismatch is useful bounded provenance evidence, not completion
of source reproduction, rights/font review, source offer or renderer acceptance.

## Evidence-only packet for the bounded outcomes

Record partial and failed outcomes as evidence even if complete reproduction
remains unresolved. Prepare a versioned compliance/evidence/d2-build-inputs
packet containing original status/complete hashed input records, compact full
logs, exact genuine tag/submodule metadata and a manifested deterministic
archive of all37 selected build-helper files including their original licence.
No helper is executed. Preserve all earlier source-review archives unchanged.
Include a read-only comparison recipe; do not introduce a new publisher/build
launcher or require native execution in ordinary Compliance. Independently
verify complete packet members/digests, source-helper archive members against
the actual gitlink object and original licence bytes, and every stated outcome.
The packet is preparation and an explicit source-availability gap record; it
does not replace/verify the final source offer or change inventory guards.
Update the source-review question links with this narrower result. Submit this
documentation-only unit after source convergence; do not invalidate frozen
PR108 checks or claim source/rights/native/signing completion.

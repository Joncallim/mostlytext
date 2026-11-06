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

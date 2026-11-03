# Preserve selected Go standard-library source notices

Continue #14's per-file runtime/source work on the verified Go 1.24.6 inputs.
The D2 publisher-source graph selects 192 standard-library packages / 1,013 Go
and assembly files. A complete read of those selected files finds 21 carrying
Sun/Cephes/fiat-crypto supplemental comments, plus distinct Go copyright years.
The four vendored Go root LICENSE texts equal the already preserved root text.
Go/PATENTS is also present in the exact compiler archive.

Baseline is stacked on #44 source 37073df2. Commit this contract before adding
inventory, notice assembly or verification code. Do not modify the older #42
source/evidence or call its root-notice correction an exhaustive runtime audit.

Add a conservative source-build attribution with the complete selected notice
comments and exact Go/PATENTS text. Bind it to the frozen Go package graph,
checksum-verified official archive, selected file hashes and exact fragment
coordinates/hashes. Keep distinct source-file comments verbatim; deduplicate only
byte-identical notices with a complete source map. Preserve every original author
and condition. Use a qualified LicenseRef for the composite source notices, not
an invented replacement grant or unsupported SPDX/legal conclusion.

The source-build graph does not prove every selected file was emitted. This
supplement is not a compiler rebuild, independent original Cephes grant clearance,
complete D2/Graphviz runtime audit, source-offer approval or final release pass.
Existing unresolved items and source/publication gates stay open. Never execute
D2/WASM/app/UI, package publication scripts, signing or arbitrary archived code.

Verify deterministic assembly and installed inventory/generation binding, actual
changed/truncated source/archive/fragment controls and missing copyright/condition
controls. Run all compliance/supporting checks, strict release without suppressing
its real blockers, locked compile-only Release and the unchanged actual notice
reader over compiled resources. Refresh the global source-review snapshot at a
new path/hash. Run hosted Compliance on the exact source; preceding full app CI
continues to qualify its unchanged runtime code, while the local Release build
qualifies the new resource corpus. Preserve earlier archives and initial failures.

# Parser fork adoption checkpoint — 9 November 2026

## Owner summary

The parser C source, Swift wrapper and Neon dependency pins are now published
in their owner forks. Hosted tests have exercised that exact chain in all three
packages. MostlyText's app still uses its previous pins. The next app change
must inherit the pending Preview integration, then qualify the complete app and
editor on one final source before claiming a performance or native fix.

This is a dated checkpoint for [issue #18](https://github.com/Joncallim/mostlytext/issues/18),
not an application dependency update or release acceptance.

## Current main and source identity

MostlyText `main` was clean at `069fea65606196c2e5148f01eafbfacfe3636da5`
when this checkpoint was prepared. The current MacDownKit and
TreeSitterMarkdown `Package.swift` files and the 24-row MacDownKit
`Package.resolved` still have the exact source hashes used by the first hosted
graph resolution:

| Current input | SHA-256 |
| --- | --- |
| `MacDown2/Packages/MacDownKit/Package.swift` | `3d43404c0a1396bbac7a1c0d052ebc31bc2c931e0ebc407356a305a5aa87d284` |
| `MacDown2/Packages/TreeSitterMarkdown/Package.swift` | `0c28b2050f598318402bd9266a4c4adec0060afc1dad904d7b251bd1ffb5c8d8` |
| `MacDown2/Packages/MacDownKit/Package.resolved` | `0a878dfe4a355ae18d0521d37540f414355180c1273baaddde313ec5460c96a4` |

The [hosted graph receipt](https://github.com/Joncallim/mostlytext/actions/runs/42487278217)
resolved the three proposed parser rows without changing the other 21 rows.
Its staged lock SHA-256 is
`1e0e187f55661e3e63e2a862853553a158d583c84055ff6cf3ebe877619e39be`.
That lock belongs to the disposable graph checkout; it is not committed to
MostlyText's app.

## Fork publication and executed package evidence

| Owner fork | Qualified head | Merge commit | Merge tree |
| --- | --- | --- | --- |
| [tree-sitter PR #1](https://github.com/Joncallim/tree-sitter/pull/1) | `1884982a418525e2e251ba331da929fccd354f3f` | `b21d3d71ac64585f3697d303d34989f5050a34f9` | `6ab06e2a3bd3af27207829694ef1899f110998d1` |
| [SwiftTreeSitter PR #1](https://github.com/Joncallim/SwiftTreeSitter/pull/1) | `7cf83c59f1d7b6fdbd6ae3b0e212c9824fbf103d` | `06d8fc06d6c8af16e2a97af0d1d0352851a3e8e6` | `6fc812ba97d55f93e2fe15950285bb9549eae388` |
| [Neon PR #1](https://github.com/Joncallim/Neon/pull/1) | `7afa1dc49511a0d154f38810725d6984968ec2e6` | `1a83e6e4aa7392cc9829d6812c85a4767989d8fa` | `838fc45986276ccfe69469e2f8aaca6997886d34` |

Each merge has the qualified head as its second parent and the same tree as
that head. The wrapper and Neon PRs change one manifest revision each; their
original licence and submodule bytes remain unchanged. The C fork's
[hosted source run](https://github.com/Joncallim/mostlytext/actions/runs/42515686273)
passes its normal and AddressSanitizer/UndefinedBehaviorSanitizer controls,
including 324 ordered subtree comparisons, Markdown lookahead and UTF-16
boundary cases. Earlier sanitizer-startup timeouts remain failed attempts.

The [complete staged package run](https://github.com/Joncallim/mostlytext/actions/runs/42520509316)
passes on macOS 26.7.2 ARM with Xcode 26.6. SwiftTreeSitter executes 36 XCTest
and 12 Swift Testing cases; Neon executes 8 and 41. Staged MacDownKit builds
and runs 3,721 Swift Testing cases in 537 suites. Its separate XCTest command
discovers zero cases, and nine existing Release-only or opt-in cases are
skipped by their original guards. All 12 recorded commands exit zero, their
log digests match the receipt, and fresh resolution retains the staged lock.
The hosted checkout is `82a59c4ded5afc1f054dbd315b5cef821af056ec`.

## Next app slice and stop conditions

[Preview PR #146](https://github.com/Joncallim/mostlytext/pull/146) is still
draft at `024103b3a0ce7d75025a5a14e7e0dacf9892973f`. Its mounted image
Copy failure is unresolved. The recorded parser adoption sequence waits for
that PR to qualify and merge, so the app pin change can inherit its final
Textual revision and every intervening main change. A private staged graph
does not substitute for that production baseline.

After Preview convergence, recheck the three input hashes and all 24 lock
rows against the then-current main. If any source input changed, resolve the
graph again on the new baseline and retain that actual receipt. Apply only the
reviewed C, wrapper and Neon revisions to the app manifests and the actual
resolved lock; update the compliance inventory, source/licence evidence,
notices and SBOM in the same change. Keep all unrelated dependency revisions.

The app candidate then needs fresh complete package and app CI, Debug and
Release builds of both the app and public `mostlytext` CLI, editor/highlighter
geometry and lifecycle tests, and a final source/tree review. The separate
test-account native editor and Release responsiveness checks must run on an
immutable, identified product. Neither the staged package run nor a green
ordinary CI result proves the original 1 MiB / 50 ms whole-edit budget,
mounted-editor safety, signing or final release acceptance. Issue #18 remains
open until its own remaining criteria pass.

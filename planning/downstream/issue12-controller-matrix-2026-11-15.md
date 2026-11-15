# External-file controller matrix extension — 15 November 2026

## Owner summary

This adds controlled app-layer evidence for external-file deletion, moves,
rapid atomic rewrites and closing during a pending file-monitor debounce.
Each test uses real temporary file bytes and the current document/editor
controller. The move tests also use the production file probe, so they check
its classification before applying the observation. No product behavior,
watcher policy or release acceptance threshold changes in this unit.

## Baseline and cases

Baseline is MostlyText `main` `67298abfc013d052dbcf8ed2b5d47e9c872899cc`.
`ExternalSourceFidelityTests` now checks:

- A same-parent, identity-preserving rename updates the document and saved
  session URL while retaining exact source, selection, scroll and disk bytes.
- A cross-parent move is classified as missing from the watched parent. The
  editor keeps dirty local text, the destination keeps its original disk bytes,
  and the recovery copy saves the draft. Cross-parent discovery is not a
  supported automatic relocation capability.
- Deletion leaves the last editor bytes visible and recoverable, without
  recreating the missing file.
- Twenty atomic formatter-style replacements converge on the last disk
  revision through a real file watcher and controller, after an independently
  observed positive replacement. The editor and disk agree and no conflict is
  invented for the clean document.
- A real deletion signal entering a long debounce is followed by disposal.
  After cancellation is acknowledged, a late probe attempt cannot mutate the
  retired document/editor. This is a controller lifetime test, not an actual
  native close-sheet journey.

The first Debug run passed the rename but timed out in the cross-parent and
deletion tests. Their fixture probed `/private/tmp/...` after the source
vanished, while the loaded `FileDocument` and controller were bound to
`/tmp/...`. On this Mac the existing-file URL had resolved through the
`/private/tmp` alias before deletion; a missing path no longer did, so the
controller correctly rejected an observation for a different bound URL.
The fixture now probes the document's actual bound URL, matching production
monitor ingress. The first failures are retained as fixture diagnostics, not
as passing attempts or as a demonstrated product defect.

The first local Release invocation omitted `ENABLE_TESTABILITY=YES` and failed
before executing tests because this app test target imports the package's
internal probe, as other Release app tests already do. The repository's
external-controller workflow supplies that setting. A second invocation
included it but omitted the same workflow's `RELEASE_PREVIEW_PROBE` compilation
condition; unrelated preview test fixtures then failed to compile. Both failed
builds are retained as local invocation errors, not product-test results.

## Focused verification

On Apple silicon, macOS 26.5.1 and Xcode 26.6, the corrected focused Debug
run passed all seven source-fidelity tests. Its local log is
`/private/tmp/mostlytext-issue12-matrix-test3.log` (SHA-256
`55ab6a946e69ec433bb9aa69c863088e8135e50441c37caa3270c414602c59c6`).
The first Debug failure log is
`/private/tmp/mostlytext-issue12-matrix-test.log` (SHA-256
`5a1be05412e1d0af21bfb5a40b2207dbc55c94f14cdbeeb923cde253ba88049b`).

The focused optimized Release run passed all seven tests on the final test
source (0.598 seconds for the suite). It used the external-controller
workflow's `ENABLE_TESTABILITY=YES` and `RELEASE_PREVIEW_PROBE` settings. Its
local log is `/private/tmp/mostlytext-issue12-matrix-release3.log` (SHA-256
`c97e571711cde4c3aa477cb1b5a7971f5339bd69fa38041cbb1efd67bc025cd9`).
The two earlier Release compile logs remain at
`/private/tmp/mostlytext-issue12-matrix-release.log` and
`/private/tmp/mostlytext-issue12-matrix-release2.log` (SHA-256
`fd806bf4e875e370364501c2d220052a9d464ddd467cbeb17f80cf06153bf896`
and `09d91ab955d7bd4790dd56dc73908c96e9c682486c699b1cb7d91db43de941a9`).
SwiftFormat, strict SwiftLint and `git diff --check` pass for the test change.
These are selected tests, not a complete package or app suite.

## Evidence boundary

These are focused app-target tests using controlled file operations. They do
not substitute for #12's interactive exact signed/notarized V1 matrix,
whole-process idle-wakeup attribution, or every conflict-close and
selection/scroll/session path. The E18 final release ledger and #8 closure
remain pending. No #12 acceptance checkbox is closed by this unit alone.

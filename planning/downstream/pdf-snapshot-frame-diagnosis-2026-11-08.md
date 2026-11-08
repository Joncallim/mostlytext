# Measure PDF snapshot canvas pagination before changing production geometry

## Owner outcome and baseline

Main9a4de425a73444864445977136f4a42ea7f73aba contains the actual original PDF
readback and character/selection diagnosis. The immutable original ordinary menu
PDF has a correct visible heading on page1 and a genuinely blank page2. Its page1
clip is468x612 and page2 clip is468x49.9194; the white canvas is468x661.9194.
Those dimensions match a794x1123canvas scaled to468printable points. This supports
a testable snapshot-canvas explanation, not proof of the historical generation
branch. The actual normal print output was not preserved separately.

Add a private native diagnostic that loads exactly the retained6978byte HTML,
with the same fixed offline CSP as production and authored JavaScript disabled.
Use unchanged current PDFSnapshotFallback.paginate on actual WebKit snapshots
at width794 and three heights: original1123, actual system printable-height
converted at the same width/scale, and1. Compare actual snapshot media boxes,
resulting page count/raw text/pixel counts and actual page PNGs. This measures
whether unused viewport height can create the observed blank slice and whether
a paper-sized or minimal canvas changes that mechanism. It does not select a
production policy, truncate intentional authored whitespace or fix anything yet.

## Ownership, trust and resource boundaries

Only new private driver/controller/workflow files and this architecture change.
Compile the exact unchanged product PDFSnapshotFallback.swift directly into the
private helper; do not build/launch the product, resolve packages, modify pins,
activate export/preview or change old validators/tests. Capture all actual helper
bytes, source/HTML/PDF/output hashes and complete first logs/artifacts. Use the
existing hosted-only runner guard at its exact fixed mostlytext-focus root,
with duplicate native identity/hash checks before NSApplication/WebKit creation.
No native/font/WebKit/helper build/runtime on CORTANA; SDK typecheck only here.

The HTML is a fixed committed own canary, never owner content or a dynamic path.
Block navigation except about:blank and all remote content with production's
fixed CSP, ephemeral WebKit store and allowsContentJavaScript=false. No authored
script evaluation, external process engine, grant, shell or network shortcut.
NSApplication is created with prohibited activation on the disposable hosted
GUI machine; this is a native framework process, not the earlier zero-AppKit
read-only helper. It does not claim native app/menu acceptance or owner denial.

Three sequential cases only, fixed input<8KiB, PDF cap4MiB, at most10output pages
per case, bounded16KiB text/page and612x792rasters. Save raw snapshot and final
PDF before reading. Write partial results after each case. Outer controller
bounds the whole native helper to150seconds and records timeout/return code and
complete stdout/stderr files under an inherited4MiB-per-file OS write limit; any failure stays failed. No widened historical
budgets, unchanged failure retry, skipped control or expected-failure waiver.

## Completion and stop conditions

1. Commit this decision before implementation. Locally strict Swift6SDK
   typecheck/format/strictlint, exact product-source preservation and compliance.
2. Freeze/publish one guarded hosted native diagnostic plus Compliance. Preserve
   complete first outcomes/logZIPs/artifacts before correction. Independently
   bind actual source, downloaded binary/input/output bytes, native observations
   and inspect actual PNGs. Differences are observations, not asserted success.
3. Record a separate production geometry/pagination decision only after observing
   these actual results. A baseline failing to reproduce is not causal evidence.
   Do not merge changed product behaviour, loosen text/page checks or claim whole
   export/normal Quit/final signed acceptance from this mechanism probe.

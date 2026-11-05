# Bound typed math raster allocation before rendering

## Owner summary and baseline

A parser-admitted equation must not request an unbounded bitmap or base64 payload.
Before switching production Preview and Export together, add a typed raw-body
renderer with explicit dimension/pixel/encoded-byte limits. Valid empty/comment-only
or spacing-only output remains valid TeX: readable source is retained with a
no-visible-output state, rather than mislabeled as malformed. This is an additive
prerequisite of shared-math-activation, not a separate export pipeline or final
resource calibration. Main remains abc3a5c8; exact dependency interfaces are PR90
0db3b39c and PR91 ef26e5c9. PR91's extended actual native 42069019008 passes all
25 tests/seven suites in 1.332 s. Whole/full CI qualification remains pending.

## Ownership and interface

Math owns a Foundation-only MathImageBudget and the existing MathRenderError. The
budget admits finite nonnegative logical bounds and a finite positive scale, then
checks rounded physical dimensions and pixel products without trapping integer
conversion/multiplication. It also checks real encoded bytes. MathRendering adds
MathImageRenderer.render(body:style:context:budget:), taking the actual opaque
SwiftUIMath validated raw body; no automatic dollar stripping occurs. Its legacy
String/span API remains compatible until joint production activation.

The initial standard safety ceilings are 4,096 logical points per dimension,
8,192 physical pixels per dimension, 16,777,216 total pixels and 8 MiB PNG per
equation. These are conservative provisional ceilings, explicitly NOT measured
final ExportResourceBudget calibration or exact resident-memory/deadline claims.
Caller-provided tighter remaining-byte budgets must be honored in the eventual
shared producer, before base64 generation or result accumulation. The subsequent
producer also needs aggregate PNG/HTML ceilings, under the existing Export budget.

## Failure and allocation order

Validate caller color components (finite 0...1) and scale first. Measure the raw
validated body with the same fixed font/style used to draw it. Nonfinite/negative
geometry is renderer failure. Zero ink bounds produce noVisibleOutput, independent
of parser validity. Over-budget geometry produces resourceLimit before constructing
ImageRenderer or asking it for a CGImage. Verify actual CGImage dimensions/pixels
again before PNG encoding, then reject encoded data beyond the budget. Pixel
ceilings bound the requested raster; checking compressed bytes after encoding does
not claim zero intermediate encoder overhead. A failed equation must keep its
original source and a source-anchored structured diagnostic in both consumers.

No local fonts, drawing, native app/helper/CLI execution or signing occurs. The
Foundation budget tests exercise exact boundary arithmetic/NaN/infinity/negative/
zero/overflow controls locally. Actual typed renderer tests compile locally and
execute only in hosted complete CI, including ordinary inline/display, comments,
tight allocation/PNG limits and logical/physical dimensions. Existing real
100-equation and legacy renderer tests remain unchanged. This unit alone closes
no Preview/Export parity, calibrated-budget or native RC issue row.

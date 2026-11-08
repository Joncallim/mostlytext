# Size the export canvas from its actual paper geometry

## Owner outcome, baseline and ready decision

Mainf12d6d357a2a67087db7022060fae798733d3ce7 integrates the exact native canvas
comparison. Native42433595643 and Compliance42433595611 pass at973e6c37; eight
executed source bindings, downloaded helper bytes, every input/output hash and
actual tested/source/current/merged tree4c932c13 match. Original1123height creates
both original failed page PNG hashes exactly; actual-paper height creates one
page with PNG identical to original page1. Minimal height changes width/pixels,
so it is rejected. The complete qualified first packet is committed here before
production changes, including original data/helper/PNGs/logs/integration proof.

Replace the arbitrary tall initial canvas with the existing fixed794width and
height derived from the same NSPrintInfo that the actual print operation uses.
This prevents unused viewport height from becoming a trailing blank fallback
page without trimming any authored content/pages. Historical generation-branch
identity is still unobserved; native mechanism and new actual adapter output,
not an invented sole historical cause, justify this correction.

## Ownership and contracts

Keep this inside the existing app PDF adapter/fallback. Add
PDFSnapshotFallback.viewportSize(for:NSPrintInfo)->NSSize?: printable width and
height subtract the actual margins from paper dimensions; require all dimensions,
margins and derived values finite, positive printable area, fixed width794 and
floor(printableHeight*794/printableWidth) in1...16384. Invalid geometry returnsnil;
the adapter refuses with its existing printConfigurationFailed before loading.
No clamping, default paper substitution, minimal-width trick or infinite frame.

PDFExportAdapter creates its two owned scratch URLs/defer and one configured
NSPrintInfo before constructing/loading its ephemeral locked WebKit view. Use
the viewport helper before layout. Pass that exact printInfo into the actual
WebKit printOperation and assign it to operation.printInfo before running;
verify its save destination as before. Keep public printInfo/configure callers,
original flags/defaults, print progress, cancellation/lease/admission/atomic
publication and output validation unchanged. Do not resize after loading,
evaluate authored scripts, change CSS, drop a page or alter pagination ranges.

Keep all original PDF tests/names/assertions. Intake only the already-qualified
nine-function hosted PDF lane and its exact source/compiled/ownership checker
from6cad5627: its own first42426662604 passes nine originals, zero skips/expected/
force/timeouts, independently verifies1625inputs/24pins/five compiled roles and
actual raw result. This qualifies only that lane, not the frozen preview candidate
which remains failed/pending and untouched. The two previously disabled native
print tests remain disabled in ordinary runs and opt in only under the existing
hosted PDF condition, retaining their original actual bodies. No preview product
activation, extra package test membership or project change is taken in.

Strengthen the existing print-configuration test with square/portrait/landscape
paper geometry, unusable margins and nonfinite geometry controls. Strengthen the
existing real short-document replacement test to require one page and its text,
while retaining actual replacement validation. Keep long/multi-page selectable
text, heading-cut ink and vector-only controls unchanged; all nine must execute
and pass in the actual bounded hosted Release app. Adapt the private canvas
comparison to use the actual production viewport helper for its paper case;
retain original/minimal controls and all old outputs as historical firsts.

## Failure, resource, security and release boundaries

No dependency/pin/new source authority or network path; original offline CSP,
JavaScript-disabled ephemeral store, navigation refusal,30second page/capture
limits,256fallback pages/256MiB product output, owned cancellation and final
publication checks remain. Native only on guarded hosted macOS26ARM. Locally SDK
strict typecheck only, style/pure source/guard/compliance; no app/font/WebKit build
or execution in the held owner account. UI/native/signing/separate-account gates
remain explicit. Existing localisation strings are reused, no new release copy.

Freeze once; obtain complete first CI, native nine-case PDF lane, canvas comparison,
Compliance and security results. Retain complete first logs/artifacts/raw results
before any correction. Independently verify actual source/pins/compiled products,
raw selections/owned lifecycle, short one-page output and long pagination. Scoped
orthogonal self-review and expected-head merge only after qualification; update
issue11 with this exact remedy and remaining whole-menu/validator/release gates.
No ordinary menu/normal Quit, source-activated export consumer or full issue closure
is inferred from app-target tests. Stop and revise the decision if typography,
line wrapping, meaningful page flow or original assertions change unexpectedly.

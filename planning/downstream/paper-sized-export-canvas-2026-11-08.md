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

## Review remediation: stable PDF content width before final validation

All six complete first workflows at3c23e399 pass and are retained before this
correction (full CI3720package/680app). This is not a waiver of the later native
review finding. Exact same boundary HTML at former versus paper height produces
794vs777wide snapshots and different typography. Independent proof binds all
eight native sources, downloaded helper and all HTML/PDF/PNG outputs for both
complete boundary firsts. Old images and changed boundary images are inspected.

The seven-case prototype3a4507ec, native42437419599/Compliance42437498897, passes
and is fully preserved here. Static html { scrollbar-width: none !important; }
restores794width, exact original short-page PNG/raw text and BOTH exact original
boundary page PNGs/raw text. The authored700pixel block still requires2pages;
its final blank page stays, while the short canary has1page. No page is trimmed.
Only root scrollbar chrome is removed; scrolling/overflow/content are not hidden.
Official WebKit support: https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
Actual native observations, not that document, qualify this remedy.

Revise production policy inside ExportService before any final-HTML receipt:
add one internal PDFCanvasStylesheet.css constant with that exact fixed rule.
ExportComposer's structuralStylesheet(for:target) adds it only forPDF; stylesheet
composition and safe companion certification use this target-specific trusted
structural CSS. HTML targets/default stylesheet callers preserve exact prior CSS.
SVGAssemblyOwnership.AuditedHeadCSS.builtIn gains an optional target defaulting
to priorHTML behaviour, checks closed references on the actual trusted structural
sheet, and mints the same target-specific stylesheet. The validated-SVG entry
passes its actual target. No new public API, post-validation HTML rewrite, script
or private WebKit view/scroller manipulation. PDFAdapter still receives the exact
accepted bytes; ordinary prepared PDF and validated PDF share the same policy.

Keep all nine original PDF names/body assertions and strengthen hardenedHTML
with policy presence. Add a package end-to-end HTML/PDF target+SVG ownership
control; strengthen existing actual app accepted-PDF-input test to require SVG
and policy while retaining exact UTF8/destination checks. Native canvas gate
retains five historical controls plus two fixed CSS candidates using the actual
production constant compiled directly with its helper. Now reject a candidate
that changes either short/boundary reference PNG/text, narrows width, loses the
short one-page output or trims the two-page authored-space fixture. Include the
actual policy source in binding/compilation/trigger paths. Same original limits.

The scanner's neutral finding at3c23 concerns mocked public POSIX pw_name/pw_dir,
not a credential; exact AST proof is preserved. Use a real pwd.struct_passwd
fixture with the same public runner identity and inert non-authentication marker,
matching the actual API record more closely. Do not suppress a scanner, erase
old findings/firsts, rotate nonexistent credentials or claim its external incident
resolved. Browser inspection is unauthenticated; no account/permission change.

Freeze a new candidate once these changes are locally style/syntax/pure-guard
checked; no local package/native build. Obtain and retain all newly triggered
complete first CI/native/Compliance/security results before further correction.
Independently verify actual app/package/native output and byte identity. Merge
only after the concrete boundary finding is remediated and all technical gates
qualify, with any actual scanner disposition honestly recorded. Main remainsf12
until then; no whole ordinary-menu/normalQuit/finalRC issue acceptance inferred.

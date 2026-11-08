# Check content width at the PDF page-height boundary before product merge

## Owner outcome and review question

The paper-sized export candidate3c23e399 is frozen pending all six complete first
workflows. Its nine actual native PDF controls, canvas comparison, public CLI and
shared math/heading pass; full CI is still running. Mainf12d6d35 remains unchanged.
A scoped review notes actual minimal-height WebKit snapshots shrink from794to777
when the document overflows its viewport. A document whose height lies between
the proposed1038point canvas and the former1123point canvas may therefore change
content width despite an unchanged nominal view width. This is a hypothesis from
actual observed scrollbar behaviour, not a confirmed production regression yet.

Run a separate never-merge native mechanism comparison from the frozen candidate,
without correcting or publishing changes to its production source. Keep the
original three cases and exact6978byte source input. Add two cases derived only
from that known own HTML by a fixed700pixel block containing a fixed repeated
paragraph, before the closing body tag. Compare old1123and actual-paper heights.
Record the exact hardened derived HTML bytes/hash as well as existing native
snapshot boxes, full paginated PDFs, raw text and PNGs. This asks whether width,
wrapping or meaningful page flow changes; it must not trim authored whitespace.

All earlier cases/outputs stay historical; outer150second and4MiB-per-file limits
stay, five fixed cases only. The helper still runs only on the admitted disposable
hosted Mac; no local WebKit/AppKit/font execution. Main/PR155 product, tests,
assertions, package/pins and ordinary native PDF lane remain frozen and unchanged.
Every receipt remains diagnostic-only, never release qualification. Preserve the
complete first native/Compliance outcomes before correction. If actual boundary
width/flow changes, write a separate product-policy/remediation decision before
changing production or merging the candidate. No actual regression or cure is
inferred solely from a different canvas height or a passing general CI check.

## Actual first review finding and narrowly bounded prototype

Complete first native42436428460 and Compliance42436524450 both pass ata35abe57.
Actual derived boundary HTML SHA5a3918742518aad9b525ce37485309ab5b0e46ddda013ba3e15306d36aa6894b
is identical for both boundary cases, with20fixed repeated markers. The former
1123canvas yields snapshot794x1123 and ink15482/0 across2pages. The paper-sized
1038canvas yields777x1053 and ink15798/0 across2pages. This confirms the content
width and typography drift at that boundary. Keep production PR155 unmerged,
even if its original general/native checks pass. The complete first logs and
all actual HTML/PDF/PNG/helper/receipt records are preserved before correction.

Prototype only: retain all five controls; add css-paper and css-boundary-paper
at the actual paper height using a fixed static head style
html { scrollbar-width: none !important; }. It hides only root scrollbar chrome,
without overflow:hidden, script, content trimming or viewport-collapse changes.
WebKit's official Safari18.2 notes support scrollbar-width:
https://webkit.org/blog/16301/webkit-features-in-safari-18-2/
Use the actual hosted results to establish behaviour, not the documentation alone.
All actual hardened HTML bytes/hashes and output observations remain captured.
Seven fixed cases, same150second/4MiB-per-file bounds, no product source change.

If it preserves794width, original short-page pixels and authored boundary page
flow, define a separate shared PDF stylesheet decision before production changes.
Both the ordinary and validated SVG PDF compositions must receive this policy
BEFORE their exact final HTML validation/publication receipt; never rewrite a
ValidatedExportHTML's accepted bytes afterward. HTML exports/browser scrollbars
must remain unchanged. No new ad-hoc script or private WebKit view API. Preserve
complete first prototype outcomes before selecting or coding the product remedy.

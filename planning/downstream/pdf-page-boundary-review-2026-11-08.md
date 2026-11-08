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

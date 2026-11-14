# Near-page-limit PDF calibration

The current Release export calibration has a 200-section fixture that prints
103 paper-sized pages from 305,964 Markdown bytes on the hosted macOS 26.6
runner. It caught the earlier oversized-page pagination defect and its first
clipping repair. The output is still well below the 256-page refusal bound,
so that measurement alone does not characterize print time, memory and source
retention nearer the page limit.

This follow-up keeps the original 200-section control and adds a 460-section
actual WebKit/AppKit print through `ExportService`, `PDFExportAdapter` and
PDFKit on the same guarded Release runner. It requires 200–256 physical paper
pages, every source heading in extracted text, retained PDF bytes/digest,
per-page text lengths, prepare/print timings and app/WebKit high-water samples.
The exact-head verifier requires five distinct successful test cases and both
retained PDF artifacts. The hosted artifact permits an independent visual and
text-boundary review before deciding whether the 256-page policy is safe.

The first hosted run completed all five cases but failed that independent
review: the 236-page output contains clipped/fragmented body text at page
transitions despite all 460 headings surviving. Reinspection of the exact
PR #273 artifact also found the same defect in its 200-section result; its
aggregate 4,800-sentence count hid one missing and one duplicated section
sentence. The next diagnostic captures whichever pre-pagination PDF sources
the actual path used: validated AppKit print and/or WebKit vector snapshot.
The hooks compile only under `EXPORT_BUDGET_PROBE`; the normal Release app has
no capture callback or changed export result. Comparing those source pages
with the retained paper-page result will locate whether the source PDF seam
or our pagination introduced the damage. Both failed visual results remain
preserved.

This is a near-page-count calibration, not a near-256-MiB PDF or a complete
resource-budget freeze. The 20-case HTML/resource ramp retains its measured
8/24/32 MiB source, 8/24/32 MiB single-resource, 512 distinct resource,
65,536 occurrence and near-128-MiB final HTML controls. On that earlier
runner, the near-final HTML case used 834 MiB app peak RSS and the aggregate
64-MiB case 664 MiB; those are fixture/cohort observations, not a memory
guarantee for every export. The final signed-app journey remains separate.

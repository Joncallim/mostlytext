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

This is a near-page-count calibration, not a near-256-MiB PDF or a complete
resource-budget freeze. The 20-case HTML/resource ramp retains its measured
8/24/32 MiB source, 8/24/32 MiB single-resource, 512 distinct resource,
65,536 occurrence and near-128-MiB final HTML controls. On that earlier
runner, the near-final HTML case used 834 MiB app peak RSS and the aggregate
64-MiB case 664 MiB; those are fixture/cohort observations, not a memory
guarantee for every export. The final signed-app journey remains separate.

# PDF snapshot fallback without a pathname

## Owner summary

When macOS printing returns an unusable PDF, MostlyText asks WebKit for a
vector snapshot and splits it into paper-sized pages. The fallback previously
wrote those pages to a random-looking filename beside the chosen output. That
filename was outside the final export admission until after the write. A
different file or symlink could therefore be placed there before the write.
The fallback now builds the PDF in memory, validates its bytes, and sends only
those accepted bytes to the existing destination publisher.

## Baseline and boundary

This slice starts from `main` `5b08629219cfae0e0f8cfc3b478c78855aa2a373`.
The ordinary print pass still uses an AppKit printer scratch pathname and is
outside this change. Its cleanup/ownership boundary remains an open issue #11
item. The selected final destination is still admitted by
`ExportDestinationAdmission` and published atomically by `ExportFilePublication`.

## Contract

`PDFSnapshotFallback.render` and `paginate` return immutable `Data`. They take
no output URL. Existing page geometry, maximum page count, complete source
snapshot admission, and the provisional 256 MiB PDF ceiling stay in force. A
multi-page WebKit snapshot can be returned unchanged; a single tall page is
split through a Core Graphics data consumer. The adapter checks cancellation
and its export lease after rendering, validates the same returned bytes with
PDFKit, and publishes through the existing admitted destination. Invalid or
oversized output fails without a snapshot file or destination mutation.

## Verification and limits

The two existing vector pagination tests now inspect returned bytes through
PDFKit/Core Graphics, including selectable text and painted page-boundary
pixels. The hosted genuine PDF probe exercises the ordinary print route and
fallback policy on macOS 26. Complete CI checks compilation and app tests.
This is a pathname-write removal, not a final PDF memory calibration or proof
that the printer's separate scratch path is owned. The 256 MiB ceiling is
checked after Core Graphics finishes building the output; its allocation
profile still requires Release budget evidence before issue #11 closes.

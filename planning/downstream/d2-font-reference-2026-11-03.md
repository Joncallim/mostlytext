# Compare D2 font tables with the publisher font release

Baseline main d944c3de. The existing D2 LC-03 item retains Liberation Mono RFN
review. The embedded font names Version 2.00.5. Compare its exact already-hashed
WOFF tables with the original project's published 2.00.5 TTF archive, linked by
that project's release record. This is evidence only: do not replace the font,
rename its family, change renderer/dependency bytes or claim legal clearance.

Use only Python standard-library parsing after whole-input SHA-256 admission.
Read a unique regular TTF member without extraction or source execution. Compare
all decompressed tables without masking real differences; record signed underline
position and fixed-pitch metadata, exact differing byte offsets and all per-table
hashes. Pin input archives and output. Corrupted WOFF or upstream archive must
reject before parsing. Preserve all six release failures and the existing font
KEEP decision. This narrows the review question; it does not resolve original
conversion provenance, equivalent-version status or independent owner/counsel
review. Publish no binary/source object and run no application/native path.

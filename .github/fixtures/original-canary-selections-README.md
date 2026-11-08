# Exact original native PDFSelection fixture

`original-canary-selections.json.gz` is the complete exact JSON downloaded from
native run [42432138600](https://github.com/Joncallim/mostlytext/actions/runs/42432138600),
source `3bcb2e16`, artifact `actual-original-pdf-readback/actual-pdf-readback.json`.
Uncompressed SHA256: `beb1f04a66d47fb3a79a4699d67fb488c98d6509035fdbe9835a1ec947b641e0`.
It describes only original failed PDF `ce2b5cc9`; its two pages and original
raw-canary refusal are preserved. The pure controls use actual PDFSelection
rectangles, not raw characterBounds, whose index alignment is unproved.
The native qualifier independently reads both immutable actual PDF bytes.

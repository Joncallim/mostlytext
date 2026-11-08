# Qualified retained-output PDF canary

These 15 exact gzip records preserve both complete first workflow metadata and
whole workflow log ZIPs, actual input PDFs, native selection JSON, complete
stdout/stderr, receipt and independent source/binary/integration readback.
Every record has original byte count and SHA256 in manifest.json. Zero-byte
stderr is intentionally retained. No excerpt is labelled a complete log.

Source `1eb8d941`, actual tested `4b17469c` and integrated main `23de8c25` have
identical tree `679ef068afcd30d0c1695c99dc2abfc2f53168cc`. Actual merge parents
are prior main `78676210` and source. Canonical integration was clean.
All eight executed source hashes, both input hashes and downloaded actual helper
bytes were verified. The compiled helper remains in the original native artifact
and retained external first; its hash is included, its bytes are not in this packet.
The historical independent reader records its actual environment paths.

[Native first 42447473633](https://github.com/Joncallim/mostlytext/actions/runs/42447473633)
and [Compliance first 42447473478](https://github.com/Joncallim/mostlytext/actions/runs/42447473478)
pass. Actual single-character selection strings/rectangles for both first pages
exactly match the earlier original observation, while page count distinguishes
the rejected original two-page PDF from the accepted corrected one-page PDF.
All 20 heading characters reconstruct by visible position. Fourteen adversarial
controls and 332 Compliance tests also pass. Review is scoped orthogonal self-review.

This is fixed-fixture oracle qualification. No product or dependency changes,
app/GUI launches, ordinary-menu export, Cancel/normal Quit, font-fidelity or exact
signed release acceptance follows. PR147's original failed validator is unchanged.

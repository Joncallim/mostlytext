# Narrow the remaining parser-position review with actual JavaScript structure

## Owner summary

The earlier index leaves 3,528 parser references requiring review after the
credited runtime preamble. A large share appears to be imports, export-binding
tables, name-retention calls and punctuation. Parse the exact reproduced outputs
and classify only those concrete structures, leaving all other positions explicit.
This makes the remaining review smaller and inspectable without inventing code
ownership or treating syntax classification as rights clearance.

## Baseline, scope and method

Baseline main 1ec610d571a2dbdef235643d69098d581afbc2fd. Preserve the original
module map, original 3,980-position index and all existing notice/provenance
records. Build a separate coordinate/hash-only classification packet for the
3,528-reference remainder, bound to the complete 192-member reproduction receipt,
all original member hashes and the unchanged shipped Mermaid bytes.

Use a pinned Acorn JavaScript parser in an owned non-application fixture to parse
actual copied published/reproduced parser JavaScript. This is an audit tool, not
a runtime or CI dependency. The portable recipe accepts explicit source/tool/index
paths and rejects changed source bytes. Offline standard-library CI validates the
pinned receipt, exact one-to-one row/outer-coordinate/member correspondence and
category totals. No code text is copied into the classification output.

Classify import declarations; strict namespace-export calls whose properties are
zero-argument arrows returning identifiers; name-retention calls in static class
blocks; and punctuation-only lines whose actual parser tokens confirm syntax,
not string/template/comment contents. Use actual UTF-16 coordinates, not Python
code-point offsets. Every position outside those narrow constructs stays unknown.
Missing rows, changed input hashes, unsupported categories, false review/rights
clearance or edited totals fail verification. Do not promote unresolved versions,
infer an original grant, remove notices or reduce any strict release predicate.

## Verification and completion

Run the real syntax parser and the offline validation against all original rows.
Use actual fixture mutations to prove that executable export getters, a changed
name-retention call and punctuation inside a template are not classified as the
reviewed constructs. Include supplementary Unicode coordinates and mixed syntax
boundaries. Add offline negative controls for missing/duplicate rows, changed
source/coordinates/counts and false clearance. Run all compliance controls and
source checks; notices/SBOM, app/runtime/pins/build inputs must stay identical.
Hosted exact-head Compliance and merge-tree verification precede integration.
Update #14 with exact classified/unknown counts and remaining independent review.
No app/native launch, signing, publication, dependency or product change occurs.

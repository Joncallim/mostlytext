# Private source-publication staging for MostlyText 1.0.0

## Owner summary

This prepares one reviewable, versioned directory containing the current
notices, software bill of materials (SBOM), and the existing D2 and Graphviz
local source-review packages. It gives the owner concrete files and hashes to
inspect before a separate source-only publication decision. It does not upload
anything, change a source offer to verified, decide remaining rights questions,
or authorize an application release.

The published site lives in `Joncallim/mostlytext-site`; this source branch does
not edit that repository or the retained `website/` snapshot. A private output
must be placed outside the Git repository. Its `REVIEW_ONLY.json` and both
component pages state that the packages are still unapproved review objects.

## Baseline and inputs

Baseline: clean `Joncallim/mostlytext` main
`d605d92ed6adc196bf0e679461dd8896443f6847` on 9 November 2026.
`compliance/inventory.json` targets planned version 1.0.0. D2 0.1.33 and
Viz.js 3.30.0 source offers remain `planned`, with no public material list or
retrieval receipt. The D2 37-file review archive has exact SHA-256
`07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02`.
The last Graphviz 57-file archive is a dated snapshot: its embedded notices
and SBOM differ from current main. Build a new archive using the existing
`prepare_graphviz_offer.py` verifier; do not relabel or overwrite the old one.

## Staging contract

The new `stage_source_publication.py` accepts only the reviewed D2 archive, a
Graphviz archive reconstructed byte for byte from current reviewed inputs,
the current generated notices and SBOM, and the D2 browser patch already
verified inside its archive. The ordinary source compliance check must pass.
Both inventory offers must still be planned at the versioned location. The
result is a single-use output directory containing:

```text
REVIEW_ONLY.json
1.0.0/THIRD_PARTY_NOTICES.md
1.0.0/sbom.cdx.json
1.0.0/SHA256SUMS
1.0.0/d2/{index.html,d2-source-review-bundle.tar.gz,d2-browser.patch}
1.0.0/graphviz/{index.html,graphviz-source-review.tar.gz}
```

`SHA256SUMS` covers every staged versioned file except itself. The separate
review receipt binds the inventory, material sizes and digests. A repeat
invocation refuses to overwrite; `--verify-only` rechecks every expected byte
against current source and rejects missing, extra, changed or linked files.
No additional private document, signing material, credential or application
binary is selected as a payload input. The two source archives retain their
own explicitly limited review status and existing member-level verifiers.

Five Graphviz reproduction `README.md` members contain absolute local build
paths under `/Volumes/Fast SSD/`. These are already in the committed evidence
used by the existing archive assembler. This staging unit preserves those
reviewed bytes; a publisher must review the path disclosures before approving
public hosting. The byte verifier establishes identity, not publication safety
or corresponding-source completeness.

## Procedure and stop conditions

Use the retained Graphviz input folder named in
`compliance/evidence/viz-js-3.30.0/README.md`, and the retained D2 archive
named in `compliance/evidence/d2-0.1.33/README.md`. First run the existing
Graphviz archive assembler with a new local output filename, then stage and
verify the versioned directory. Keep both outputs in private build storage.
The first private run on 9 November 2026 produced and verified the eight
versioned files plus `REVIEW_ONLY.json`. The D2 package retained SHA-256
`07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02`;
the freshly assembled 57-file Graphviz package had SHA-256
`7e045b5179ef4b9a6a8b0fdc02ac0ce2f8b7dde4fff6a66ef45ed6784c65e98e`.
The staged notices and SBOM hashes were respectively
`1e19c978f81682e60cd2cdf20a18122f2106c73a26c67e9ddebcca5b39354341`
and `53159298f7c0c6d986bb79d718f90efa66e385715c50f5a6c82748e5eeb12893`.
The staged `SHA256SUMS` hash was
`41f92f83ca9f2c6058b02659f7a047f00df4348e464303cce4f1e6ffb2749b59`.
An older 57-file Graphviz archive failed member-byte verification because its
embedded notices and SBOM predated current main. It was not used for staging.

Stop if ordinary compliance, source/member verification, inventory offer state,
current generated texts, file type, output isolation, or byte-for-byte staging
verification fails. Do not weaken the six strict release predicates to make
this private preparation appear complete. Independent corresponding-source,
font, nested-rights and publisher review still precedes approval. Public
source-only publication requires the explicit authorization and anonymous
retrieval sequence in `compliance/ARCHIVE_PLAN.md`; final signed-artifact and
native checks remain separate.

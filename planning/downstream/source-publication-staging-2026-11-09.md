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
At this `d605d92e` baseline, the then-last Graphviz 57-file archive was a
dated snapshot: its embedded notices and SBOM differed from the current
source. The refresh below uses `prepare_graphviz_offer.py` to build a new
archive without relabeling or overwriting the old one.

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

Five Graphviz reproduction `README.md` files in the repository contain local
build-machine paths. The current assembler replaces exactly those five paths
in its package copies, leaves the committed evidence unchanged, and rejects
other local user or volume paths in assembled non-upstream material. The first
private stage below predates that correction and must remain historical review
evidence rather than a publication input. The byte verifier establishes
identity, not corresponding-source completeness or publication approval.

## Procedure and stop conditions

Use the retained Graphviz input folder named in
`compliance/evidence/viz-js-3.30.0/README.md`, and the retained D2 archive
named in `compliance/evidence/d2-0.1.33/README.md`. First run the existing
Graphviz archive assembler with a new local output filename, then stage and
verify the versioned directory. Keep both outputs in private build storage.
The first private run on 9 November 2026 produced and verified the eight
versioned files plus `REVIEW_ONLY.json`. The D2 package retained SHA-256
`07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02`;
the then-current 57-file Graphviz package had SHA-256
`7e045b5179ef4b9a6a8b0fdc02ac0ce2f8b7dde4fff6a66ef45ed6784c65e98e`.
The staged notices and SBOM hashes were respectively
`1e19c978f81682e60cd2cdf20a18122f2106c73a26c67e9ddebcca5b39354341`
and `53159298f7c0c6d986bb79d718f90efa66e385715c50f5a6c82748e5eeb12893`.
The staged `SHA256SUMS` hash was
`41f92f83ca9f2c6058b02659f7a047f00df4348e464303cce4f1e6ffb2749b59`.
An older 57-file Graphviz archive failed member-byte verification because its
embedded notices and SBOM predated current main. It was not used for staging.

## Current private refresh — 9 November 2026

From clean main `ffe692feef9c7c8f45ccd2dea1f88e31115aeae6`, the current
Graphviz assembler reproduced a new package with 57 payload files and one
manifest member: SHA-256
`f2fba2c66a79f3345cc2db1eca515ae570175904f1b96449edf9937c4341d8b2`.
The retained reviewed D2 archive remains the same 37-file package. The
versioned private stage contains eight files plus `REVIEW_ONLY.json`; it passed
creation and independent `--verify-only` readback. Its `SHA256SUMS` is
`34d25f2940960f7f8e4ecbb8cb1d47708d0ca10933a09f0442c86ef2a9758b3c`
and its review receipt is
`8aa596211d4bbff06c95f9927ba37552ce52a5a21a2a97af05cb52819b9deab9`.
Both private outputs are retained outside the repository. Their current notice
and SBOM snapshots are still dated preparation inputs, not final signed-app
bytes. No source-offer status or public URL changed. Rebuild the snapshot if
distribution inputs change; do not reuse the older stage for publication.

Stop if ordinary compliance, source/member verification, inventory offer state,
current generated texts, file type, output isolation, or byte-for-byte staging
verification fails. Do not weaken the six strict release predicates to make
this private preparation appear complete. Independent corresponding-source,
font, nested-rights and publisher review still precedes approval. Public
source-only publication requires the explicit authorization and anonymous
retrieval sequence in `compliance/ARCHIVE_PLAN.md`; final signed-artifact and
native checks remain separate.

# Cytoscape and two borrowed helper notices in Mermaid

## Owner outcome

The distributed notices now retain Cytoscape's own complete MIT text and two
additional MIT notices: Gaëtan Renaudeau's Bézier easing and jQuery-derived
events. They are separate conservative attributions, not a claim that all
Cytoscape/Mermaid nested code or legal obligations are resolved. The renderer
bytes and dependency versions are unchanged; MostlyText #14 stays open.

## Exact shipped inclusion

The shipped Mermaid 11.17.2 bundle (SHA-256
581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8) matches its
official npm archive. Its exact generated source map (SHA-256
43cd977e8e0f351d6c47d31302c564f1c21fdc1e0be0d9e46370ee5e23cea004) reaches
Cytoscape 3.34.0's dist/cytoscape.esm.mjs, byte-identical to the official package
member (SHA-256 9ffbc8172ca3bd6723fba3513f96194f0e4c98225e00f380948f285869517803).
Cytoscape's publisher-reported source commit is
[22716bfb75834b56fa6679648b0abb06f4ae691c](https://github.com/cytoscape/cytoscape.js/tree/22716bfb75834b56fa6679648b0abb06f4ae691c).
This is publisher provenance, not a rebuilt/publisher-signature attestation.

[mapping.json](mapping.json) records archive/member/text hashes and real generated
positions, not mere source-list declarations or comments:

| Credited fragment | Cytoscape source lines (1-based) | Generated references | Required specific code probes |
|---|---|---|---|
| Bézier generator | 14979–15108 | 453 across 108 lines | calcBezier and getSlope declarations: 9 references each |
| jQuery-derived event object | 12234–12324 | 227 across 63 lines | default/propagation/immediate-propagation setters: 3 references each |

The verifier requires every probe to map to generated code. Other code in the
same region, another source's coordinates, comments or an unmapped source-list
entry cannot substitute for that proof. Mappings establish emitted provenance,
not semantic reachability or native behavior. The full root MIT file is copied
verbatim from the integrity-checked Cytoscape archive.

## Licensed references and the adaptation limit

Cytoscape expressly credits each helper under MIT but does not identify its exact
original adaptation revision. These are matching licensed references, not an
invented original-version or complete-package-inclusion claim:

- [BezierEasing v2.0.3 source](https://github.com/gre/bezier-easing/blob/18f06f5d058184690f5975a243e5bcfcba2e89c4/src/index.js)
  and its [complete MIT text](https://github.com/gre/bezier-easing/blob/18f06f5d058184690f5975a243e5bcfcba2e89c4/LICENSE),
  Copyright (c) 2014 Gaëtan Renaudeau. The polynomial coefficients, Newton/slope
  and subdivision helpers match the credited algorithm; Cytoscape adapts its
  validation/wrapping.
- [jQuery 1.11.0 events](https://github.com/jquery/jquery/blob/91cd1587ed4a1d4f3834227e8eb3cc30cb385409/src/event.js)
  and its [complete MIT text](https://github.com/jquery/jquery/blob/91cd1587ed4a1d4f3834227e8eb3cc30cb385409/MIT-LICENSE.txt),
  Copyright 2014 jQuery Foundation and other contributors. The event state and
  prevention/propagation methods match the explicitly credited event-object
  adaptation; Cytoscape adds its own fields and behavior.

The two complete license files are byte-for-byte copies of these immutable
references. [references.json](references.json) pins their source/text hashes,
matching source markers and exact mapped-region probes. The inventory uses
kind attribution and states the adaptation limit; it does not create fictitious
whole-package version records for these helpers. Notices and SBOM are generated
with the same change. All existing notices/attribution remain intact.

## Replay and controls

Preserved npm inputs:
/Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18.
New immutable upstream captures, full replay/control logs and API records:
/Volumes/Fast SSD/CORTANA-Builds/compliance-convergence-20261103/upstream.
Nothing was installed or executed from either source package.

```sh
python3 compliance/tools/audit_cytoscape_attribution.py \
  --evidence-dir /Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18 \
  --reference-dir '/Volumes/Fast SSD/CORTANA-Builds/compliance-convergence-20261103/upstream' \
  --shipped MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js \
  --licence-dir compliance/licenses --output /tmp/cytoscape-attribution.json
cmp compliance/evidence/cytoscape-borrowed-attribution/mapping.json /tmp/cytoscape-attribution.json
python3 -m unittest discover -s compliance/tests
```

Hosted negative controls cover changed bytes, missing/repeated/outside/reordered
boundaries, source identity, comment-only mappings, non-probe substitutions and
missing individual probes. All ten full-input corruption controls pass, including coherently rewritten
archive/registry pairs; logs are retained with the new captures. Replayed npm integrity, source-map identity and distributed source/
license comparisons fail closed. Source checks do not accept a signed artifact.

## Remaining review

Ralf Engelschall's Thenable, Koen Bok/Framer spring code, other Cytoscape generated
or embedded helpers, Rough.js prebundles, original resolution for versionless
candidate paths, unmapped parser regions and the rest of the captured package
texts/versions remain open. The existing React-derived KaTeX notice remains in
place and is not replaced by this change.

A historical-reference warning matters for the next reviewer: Framer 0.5.0
(27de5feef92c477c5465188f3587dfe0fd961bdc) and 2.0
(6fd264c787a410e47ea4d3e8e6e32d5f99d5ac8c) carry the same BSD-style text, SHA-256
e7db6b6131fef9133e7a689822c2e40e446a0d1f3e942f4fce14fa67cd5ed8c3, while the
Cytoscape spring header says MIT and names no version. Those historical tags
are not proven to be the actual adaptation origin. Do not infer the current
license from them, substitute a guessed MIT text, or declare the spring audit
complete. A later immutable source/license match or appropriate review is needed.

All six strict release failures remain. Source-offer approval/publication and
anonymous retrieval, native license surfaces, real installation/signing and the
exact final artifact remain separate gates. No legal clearance, release or
website deployment is claimed by these scoped notice additions.

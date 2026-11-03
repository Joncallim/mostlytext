# Thenable's declared MIT terms — 3 November 2026

Ralf S. Engelschall's authentic Thenable 1.0.7 source explicitly declares MIT and
links the Open Source Initiative's standard text. The emitted Cytoscape fallback
preserves the author's credit, the MIT declaration and Thenable/1.0.7 identity.
There is no standalone upstream LICENSE file at the retained tag. This notice
therefore records what was actually done: the author's existing credit and
MIT declaration followed by the complete, verbatim canonical permission,
condition and disclaimer paragraphs named in that declaration. It does not
invent an upstream file or reinterpret a license-ambiguous declaration.

## Source and construction

- Authentic reference: [rse/thenable at b7ee46032b4be96acf74cb188ace7acc39f1613c](https://github.com/rse/thenable/blob/b7ee46032b4be96acf74cb188ace7acc39f1613c/thenable.js),
  SHA-256 15d5267aeaa15d3dfeac1ca6a97378189d693d75ee26130afa342b6fcdfb97ed.
- Declared terms: [OSI MIT](https://opensource.org/license/mit), captured on
  3 November 2026. The [three exact paragraphs](osi-MIT-terms.txt) have SHA-256
  748c15c2a285ef74aec280f2e72bd98482b96bd0e2da0d8f0fde934fa88e2e16.
  No template copyright-holder placeholder is distributed. The actual Ralf
  credit from the shipped source accompanies these standard terms.
- Assembled notice: compliance/licenses/cytoscape-thenable--MIT.txt,
  SHA-256 8dd7050fe645e769344d25736c97f1e6a59830f14c83e2e93e5477a541e91b66.
  Inventory provenance explicitly describes this assembly and its two sources.

The [mapped proof](mapping.json) uses the same pinned official Mermaid bundle/map
and exact Cytoscape source as the existing credited-helper audit. The selected
fallback region has 541 generated references across 139 source lines. The actual
version assignment has three references; the circular-resolution rejection has
11. Neither a comment nor the mere presence of source content is counted as
proof that the fallback code was emitted. Generated mapping is provenance, not
proof of semantic reachability in every browser.

## Reproduce

```sh
python3 compliance/tools/verify_thenable_notice.py
python3 compliance/tools/verify_thenable_notice.py \
  --evidence-dir /path/to/mermaid-148-40b25974-2026-10-18 \
  --reference /path/to/tagged-thenable.js --output /tmp/thenable-mapping.json
cmp compliance/evidence/thenable-mit-declaration/mapping.json /tmp/thenable-mapping.json
python3 -m unittest compliance.tests.test_thenable_notice
```

Controls reject changed canonical terms, missing author credit, a coherently
changed notice/inventory digest, a fabricated upstream LICENSE path and duplicate
records. Source-map controls already reject absent/misattributed code probes and
corrupt coordinates. The raw OSI HTML and tagged source remain in the local
upstream captures; only the exact standard paragraphs and reproducible hashes
are needed for ordinary offline CI.

This closes the bounded full-text linkage gap for the explicitly MIT-declared
Thenable adaptation. It does not identify its exact original adaptation revision,
resolve Framer's distinct origin/license ambiguity, complete other generated or
embedded code review, claim independent legal clearance or authorize release.
All six strict release failures remain, with native and exact signed-artifact
acceptance separate.

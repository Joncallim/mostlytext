# Borrowed-code notices in Mermaid's Cytoscape bundle

## Owner summary

Add the missing complete Cytoscape MIT text and MIT notices for two credited
helpers in the shipped
Mermaid dependency: Gaëtan Renaudeau's Bézier easing and jQuery-derived events.
Keep the exact app/renderer/dependency bytes and release gates unchanged. This
closes two bounded attribution units under MostlyText #14; it does not complete
Cytoscape/Mermaid's embedded-code audit or legal/release acceptance.

Baseline is main 9081b7de6585e132eff2b868c3b264eadfe6fbfb. Existing source-map
helpers and the partial Mermaid audit link the shipped 11.17.2 bundle to the
exact Cytoscape 3.34.0 dist/cytoscape.esm.mjs. Parent MIT metadata and declared
package ranges are insufficient proof for embedded notices. The earlier React/
KaTeX attribution supplies the existing conservative-attribution inventory shape.

## Inputs, ownership and invariants

Use integrity-checked preserved Mermaid/Cytoscape npm archives and official
immutable GitHub source/license references. Parse archives/maps as data only;
never install or execute packages. The new compliance helper must bind the exact
shipped bundle, outer map, Cytoscape archive member, credited code regions,
generated mapping references, upstream reference source and distributed license
bytes. Capture exact source/header hashes and mapped code counts. Missing,
changed, duplicate or unmapped evidence fails. Do not treat a sources-list entry
or a comment alone as emitted-code proof.

The two upstream references provide matching licensed source and complete license
texts. Cytoscape does not specify exact original adaptation revisions: report
that limit and do not invent ancestry or claim the complete upstream packages
ship. Use kind attribution, preserve each captured license verbatim, and regenerate
notices/SBOM with the inventory change. Correct the inventory’s dated development-
name note to the already-implemented MostlyText 0.1.0 identity; do not change the
planned 1.0.0 inventory version or release status. Do not alter the two existing parent
renderer resources, dependency locks, signing policy, native protections or tests.

Thenable/Ralf and Framer/Koen spring attribution, other prebundles (including
Rough.js), generated/unmapped helpers and content-matched candidate provenance
remain open. Historical Framer 0.5/2.0 license references are BSD-style while the
Cytoscape credit says MIT. This mismatch is a review lead, not permission to infer
current obligations or substitute an arbitrary license. No Framer distribution
record is finalized by this tranche.

## Verification and completion boundary

Replay the full audit offline against the real preserved inputs. Negative controls
must reject changed shipped bytes, archive/map/source identities, upstream sources,
distributed texts and absent mapped fragment code. Hosted fixtures cover the
reusable range/byte-integrity logic without requiring external archives. Run the
full compliance suite, source check and generated-file comparison. The strict
release check must retain the existing six unresolved requirements; refine the
Mermaid residual description to actual remaining work without clearing it.

Compile the unchanged Release app with the new bundled notice and check its
artifact inventory; do not execute the product or UI on the owner account. Hosted
Compliance and normal product CI, if dispatched, remain distinct from native and
exact signed-artifact acceptance. Record results and remaining gates in #14 and
the current acceptance guide, then merge through a ready PR. Preserve failures,
source hashes, raw upstream captures and source-worktree binding.

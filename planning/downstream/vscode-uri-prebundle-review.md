# Qualify the nested URI prebundle without guessing publisher inputs

MostlyText already distributes the complete selected path-browserify MIT text.
The remaining technical question is which earlier build placed that code inside
vscode-uri 3.1.0, before Mermaid's reproduced outer parser build consumed it.
This unit compares the upstream tagged source and frozen dependency resolution
with the actual published archive. It may establish reproducibility or narrow
a mismatch; it cannot manufacture signed publisher provenance or rights clearance.

## Baseline and boundaries

Start from main `121e2f2f49aac61253bcb99ed7cc8fc9417f502f`, MostlyText #14.
The original content-only Mermaid mapping is immutable. Parser reproduction
already establishes the vscode-uri 3.1.0 archive as an outer build input. Its
registry metadata has no gitHead or attestation tying it to a source revision;
the upstream v3.1.0 tag resolves to
`edfdccd976efaf4bb8fdeca87e97c47257721729`. Treat that commit initially as a
candidate. Do not turn a matching root manifest into proof of earlier compilation.

Allowed source execution is the integrity-checked upstream JavaScript build in
an owned directory, with install scripts disabled and original manifests/locks.
No product, app/helper, AppKit/WebKit or local app-target test executes. No runtime,
package pin, font, source-offer/publication, signing or native acceptance changes.
Independent review and all six strict release predicates remain binding.

## Ordered work

1. Capture the official registry/archive and tag/source identities. Verify the
   published SHA-512 and the archive already bound by the outer reproduction.
   Inspect pipeline, compiler options, locks and actual mapped source bodies.
2. Use an owned pinned Node/package-manager toolchain and frozen installation
   with lifecycle scripts disabled. Execute only the upstream production
   compilation. Record exact resolved compiler/loader/path inputs and source
   hashes before/after; never edit inputs to force a published-byte match.
3. Compare the complete relevant emitted JS/map member sets and source-map
   contents, including path-browserify. Record every mismatch and its scope.
   A real source mutation must be detected by the same comparison; restore
   exact bytes and repeat. Never substitute a hand-written mock bundle.
4. If a complete technical reproduction is obtained, add a narrowly scoped,
   pinned offline receipt verifier and meaningful refusal controls. Connect its
   proof to current shipped-map hashes. If not, retain the partial result with
   the unresolved boundary explicit. No unsupported identity promotion.
5. Reconcile the canonical review packet and issue with the observed result.
   Notices/inventory/SBOM may change only if new complete evidence supports that
   exact projection; preserve original license bytes and independent-review
   flags. Any distribution/resource change also requires full hosted checks,
   compile-only Release and actual resource readback. Evidence-only changes
   require relevant Python/source checks and hosted Compliance.

## Completion and stop conditions

The deliverable is an inspectable recipe, exact input/output hashes, actual
negative/restored controls and an honest technical disposition. Unknown publisher
source/toolchain or output differences are recorded, never solved by weakening
comparisons. Reassess this contract before a new build lane, package resolution,
runtime dependency or attribution/grant decision. A source match is not unique
historical origin, a new license grant, final artifact or native acceptance.

## Qualified result

The complete compressed 3.1.0 npm archive reproduces byte-for-byte, including
all 17 payload members. All 13 JS/map/type files match separately; 23 original
source files remain unchanged. The tagged frozen lock selects Webpack 5.94.0,
path-browserify 1.0.1 and the recorded TypeScript/loader inputs. Both original
and portable recipes and repeated npm packing return the same archive SHA-256.
A real source error-literal mutation produces five refused members; restoration
returns all 13 matches. Fourteen offline controls and raw-capture replay qualify
this technical packet, without any inventory, notice/SBOM, runtime, source-offer
or release-predicate change. Publisher execution remains unattested and the
original candidate/independent-review fields are retained. See
[the full reproduction packet](../../compliance/evidence/uri-prebundle-reproduction/README.md).

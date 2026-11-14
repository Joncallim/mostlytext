# Release preparation ledger (MostlyText #14)

## 14 November 2026 remediation candidate

The current #14 branch adds scoped Velocity, ELK, JavaScript Brotli and JamaJS
notices, preserves the old D2 font evidence, and replaces only the Chroma font
literal and the browser bundle's compressed WASM with a controlled Go build.
The official Liberation Mono 2.00.5 TTF and the new WOFF have all 18 sfnt
tables byte-identical; the old font had only 15 matching tables. The new
browser resource passes local D2 renderer/integration tests. See
[the font/build record](evidence/d2-font-replacement/README.md) and
[nested browser audit](evidence/d2-browser-nested-inputs/README.md).

The Graphviz link-stage union now lists all 489 archive/member candidates and
maps each to at least one pinned source-archive basename, while leaving actual
compiler-image file correspondence and per-file terms open. The Mermaid audit
adds the JamaJS SVD/hypot notice; Stack Overflow revision/grant questions and
the Rough.js flatness adaptation remain open. New local source-review packages
have been assembled from this branch's final notices and independently checked
against their manifests. They are review-only; the separate proposal is under
`evidence/source-offers/`. The dated main baseline had six strict failures;
this candidate reports ten because four newly explicit nested review-required
components are counted. The checker and release predicates are unchanged.

A pinned universal Release app compile succeeds locally without signing.
Its bundled D2 browser resource, D2 notice and generated third-party notices
match this source tree byte for byte. This is compile/resource evidence; the
app was not launched and final signed-artifact acceptance remains open.

## Current checkpoint — 6 November 2026

At main `c249d6dbb77feffc7f0fbe902dd00973d3416711`, ordinary source
compliance passes. The earlier seven/eight-entry counts below are historical.
The current strict
check has six failures: D2 source publication/retrieval and independent nested
source/font review; Mermaid remaining embedded/generated/candidate provenance;
Graphviz source publication/retrieval, complete corresponding-source review, and
remaining embedded/runtime attribution. The display name is now GitHub Light;
the legacy tomorrow-light identifier and resource filename remain for settings
compatibility. The theme naming item is complete.

All original parser positions, including the final 100 references, now have
technical dispositions. The complete tagged URI prebundle archive reproduces
with its frozen lock (Webpack 5.94.0/path-browserify 1.0.1); the earlier
qualified Webpack 5.88.2 body reference is not an emitting-version finding.
Historical execution attestation and independent nested-code/IP/grant review
remain separate. [The review packet](UPSTREAM_REVIEW_QUESTIONS.md) records the
specific missing inputs, without claiming they were externally requested.

All 74 mapped Mermaid package records now have their complete selected texts
distributed, with candidate-version limits retained. Four Rough.js and 16 D2
publisher source-build inputs also have registered texts. See the
[package checkpoint](evidence/mermaid-package-notices/README.md) and
[build-attribution checkpoint](evidence/nested-build-attribution/README.md). These
bounded additions do not prove complete embedded-code coverage or legal clearance.

LC-08 source implementation is complete: the About/application-menu licenses scene uses
bounded native plain text, not Textual. [Its current contract](LICENCES_UI.md)
separates implementation and resource controls from missing native acceptance.
No source-offer status, release policy, signing or protected native guard changes.
The source-only publication step still requires the explicit authorization named
in [ARCHIVE_PLAN.md](ARCHIVE_PLAN.md). Current engineering ownership and acceptance
are reconciled in [the remaining-work map](../planning/ENGINEERING_REMAINDER.md).

## Historical preparation and artifact evidence


This is an evidence-preparation record, not a release approval or legal
clearance. It is intentionally kept on the integration branch so the release
owner can review the remaining work. The 2026-10-18 font reconciliation records
an existing product decision; it does not publish source archives, sign artifacts,
accept agreements or verify the remaining source offers.

## Historical 2026-10-14 to 2026-10-19 checks

Run from the repository root on 2026-10-14:

```text
python3 compliance/tools/compliance.py check
compliance check (tree): passed, 0 unverified item(s)
```

The historical 2026-10-14 release check reported eight raw inventory entries.
On 2026-10-18, the recorded KEEP-all-12 font decision was reconciled in inventory;
the release check at that checkpoint remained blocked by seven entries. No provenance or
source-offer `status` field changed. See the
[font reconciliation evidence](evidence/swiftui-math-fonts-2026-10-18/README.md).

| Component | Blocker at the historical checkpoint | Material then prepared or still required |
| --- | --- | --- |
| `d2` — source-location verification | Planned source URL; anonymous retrieval not verified | Existing `ARCHIVE_PLAN.md` identifies the upstream package and archive evidence still required. Do not publish or mark verified here. |
| `d2` — `LC-03` | Go revision/module provenance open | Identify the D2 Go revision/modules, licences, upstream package and one-line patch. |
| `mermaid` — nested-bundle item | Complete nested attribution and distributed texts unresolved | The [generated-bundle audit](evidence/mermaid-11.17.2/README.md) now links the exact artifact, parser and mapped modules to captured licence texts. Resolve the remaining prebundle attributions/candidate-version limits before installing the complete inventory/notices/SBOM. |
| `theme-tomorrow-light` — E23 item | Naming/source decision | Existing provenance says the palette is GitHub-derived, not Tomorrow-derived; E23 must decide whether to rename or re-source it. |
| `viz-js` — source-location verification | Planned source URL; anonymous retrieval not verified | Existing `ARCHIVE_PLAN.md` identifies the exact Graphviz/viz-js material and digest evidence still required. |
| `viz-js` — `LC-02` | Complete corresponding-source offer still open | [Exact Graphviz 16.0.0, Viz.js 3.30.0 and Expat 2.8.4 inputs](evidence/viz-js-3.30.0/README.md) are downloaded and hashed against the npm backend's publisher build record. Complete package assembly/review and LC-09 publication remain. |
| `viz-js` — linked-library review | Remaining embedded-code/runtime attribution open | Expat 2.8.4 is explicitly linked and its MIT text is added. The direct linker list does not complete the Graphviz/Emscripten runtime attribution audit. |

The checker reported those seven exact entries at that checkpoint. SwiftUIMath's product-decision
entry is resolved using the recorded KEEP decision in issue #148 comments
5868785863 and 5867001043. All 12 font resources, digests, licence texts and
artifact requirements remain. Notices and SBOM regenerate byte-identically.
The unsigned local artifact check is not the final signed-artifact check, and
this reconciliation is not evidence that any source offer is publicly reachable.

The earlier retained Release app built from `7efb510c` failed three additional
artifact checks: missing repository `LICENSE`, missing generated notices and
unregistered Textual `prism-bundle.js`. Its unchanged historical record reports
ten release findings. The [new packaging and Prism audit](evidence/prism-textual-1.29.0/README.md)
resolves those three failures on a fresh app built from clean commit
`ceecea9c4a8297db6aa24e3afa9163406e4a10e5`.

That historical `ceecea9c` app's exact `Contents/Resources/LICENSE` and
`Contents/Resources/THIRD_PARTY_NOTICES.md` matched that commit's originals. The
audit accounts for every byte of the already-shipped Textual Prism bundle using
the published Prism 1.29.0 distribution/components and Textual's header/helper;
both original MIT texts are included in generated notices. All 12 font digests
remain present. Ordinary source and artifact compliance pass; both release
checks still fail on the seven entries above. No existing finding was waived.

That is unsigned distribution evidence: the linker emitted an ad hoc signature,
with no team identity or sealed resources. The build's AppIntents metadata
warning remains recorded. The `LICENCES_UI.md` packaging prerequisite is now
implemented, but its About/Help window, localisation, accessibility and final
signed-artifact checks remain open. No native UI or performance rerun is claimed
for this resource-only change.

The 2026-10-19 [Graphviz/Expat correction](evidence/viz-js-3.30.0/README.md)
changes the notice bytes again. The historical artifact pass above does not
cover these new notices. Source checks pass with seven strict release findings;
the new notices still require inspection in a rebuilt app, and the final signed
artifact remains a separate gate.

## Corresponding-source preparation boundary

`ARCHIVE_PLAN.md` is the authoritative preparation plan. The repository has
not created public archives, changed source-offer URLs, generated a release
archive, signed an artifact, or claimed anonymous retrieval. Current safe preparation follows the specific remaining inputs in
[UPSTREAM_REVIEW_QUESTIONS.md](UPSTREAM_REVIEW_QUESTIONS.md):

1. Review remaining D2 per-file/nested Go/WASM obligations and Liberation Mono
   Reserved Font Name treatment. Exact source/module inputs and selected complete
   notices are already retained; those records are not independent clearance.
2. Complete Graphviz corresponding-source, compiler-input and retained-code
   review. The five exact runtime outputs reproduce and the local manifested
   review archive includes linker/compiler/C++ evidence; neither is an approved
   complete source offer.
3. Resolve the remaining Mermaid Framer/Koen and points-on-curve grant/origin
   questions and independent nested/generated-code review. Technical parser
   classification and URI reconstruction are complete within their stated scope.
4. Preserve the completed GitHub Light naming decision and all font/notice
   requirements through final packaged-resource and signed-artifact acceptance.

Only after an owner-authorized source-only publication may the URLs and
`source_offer.status` values be updated and the release candidate checked.

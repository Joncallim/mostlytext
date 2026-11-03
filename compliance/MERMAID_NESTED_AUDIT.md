# Mermaid 11.17.2 nested-bundle audit

> Current integration — 3 November 2026: complete selected texts for all 74 mapped
> package records, 22 conservative source-build/reference attributions and the
> explicitly declared Thenable MIT terms are now distributed through PR25/PR26.
> See [package evidence](evidence/mermaid-package-notices/README.md),
> [build references](evidence/nested-build-attribution/README.md) and
> [Thenable construction](evidence/thenable-mit-declaration/README.md). Older
> capture-only statements below retain their dated meaning. Candidate originals,
> Framer and other embedded/generated origins remain unresolved; this is not full
> nested attribution or signed-artifact clearance.


## Current owner summary — 2026-10-18

The missing generated-artifact linkage is now available: the official npm archive
contains a bundle byte-identical to the shipped file and its source map. A bounded
offline audit traces mapped code through the embedded parser and captures exact
package licence texts. It exposes attribution work hidden by the old list of
21 direct dependency ranges, including two Lodash versions and React-derived
code inside KaTeX.

**Nested notice closure remains incomplete.** Seventy-two package/version records
have versioned source-map or identical parser-chunk linkage; two more are exact
content matches against named candidate archives whose original prebundle
resolution is not proved by the automated verifier. The audit also retains
3,980 parser positions with no inner mapping and concrete nested-attribution gaps.
No runtime file, dependency pin, inventory verification status or shipped notice
was changed.

See the [current evidence and reproduction guide](evidence/mermaid-11.17.2/README.md)
and [module/notice mapping](evidence/mermaid-11.17.2/module-notice-map.json).
The checker still reports the same eight release blockers. This is provenance
evidence, not legal clearance or issue closure.

## Historical precursor — 2026-10-14

The remainder records the earlier fetcher's limitations and release-lock intake.
Its generated-artifact access gap is superseded by the 2026-10-18 evidence above;
its lock entries alone remain insufficient to prove inclusion.

## Verified local evidence

- Vendored file: `MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js`
- Recorded and recomputed SHA-256: `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`
- Recorded package: `mermaid@11.17.2`
- Existing inventory evidence says the hash equals `dist/mermaid.min.js`
  from the `mermaid@11.17.2` npm tarball.
- Existing inventory records the top-level `nested` dependency ranges below.
- The official root MIT license was retrieved from
  `https://raw.githubusercontent.com/mermaid-js/mermaid/dcb694d/LICENSE` and
  matches the checked-in `MERMAID-LICENSE.txt` byte-for-byte (SHA-256
  `ec9fb67dcb25eccc416ed56e1aab819222c805a2a4bfe4cb19e7556bf2ffde80`).

The official release is verified at GitHub commit `dcb694d` from the
`mermaid@11.17.2` release page. Its official
`pnpm-lock.yaml` resolves the Mermaid package importer as recorded below. The
lockfile proves the release's resolved dependency graph; it does not by
itself prove that every resolved package's bytes are present in the generated
single-file bundle, so bundle/source-map evidence remains a required final
check.

The expected source-map URL
`https://raw.githubusercontent.com/mermaid-js/mermaid/dcb694d/packages/mermaid/dist/mermaid.min.js.map`
returned HTTP 404, as did the corresponding generated bundle path in the
source tag. Those generated files are release artifacts rather than tracked
source-tree files. The GitHub release page confirms the immutable release and
commit, but its generated asset list was not machine-readable through the
authorized fetcher. The npm registry metadata URL
`https://registry.npmjs.org/mermaid/11.17.2` was also inaccessible through
that fetcher. Thus the local bundle hash and release lock are proven, while
the generated source-map/module-content linkage remains explicitly open.

## Recorded release-lock inputs

These are the earlier audit's release-lock resolutions, not yet proof of
inclusion in the generated bundle. The workspace parser entry still needs its
exact release-package identity.

| Package | Declared range | Release-lock resolution | License text |
|---|---|---|---|
| `@braintree/sanitize-url` | `^7.1.2` | `7.1.2` | pending source package |
| `@iconify/utils` | `^3.0.2` | `3.0.2` | pending source package |
| `@mermaid-js/parser` | `^1.2.1` | workspace link | pending source package |
| `@upsetjs/venn.js` | `^2.0.0` | `2.0.0` | pending source package |
| `cytoscape` | `^3.34.0` | `3.34.0` | pending source package |
| `cytoscape-cose-bilkent` | `^4.1.0` | `4.1.0` | pending source package |
| `cytoscape-fcose` | `^2.2.0` | `2.2.0` | pending source package |
| `d3` | `^7.9.0` | `7.9.0` | pending source package |
| `d3-sankey` | `^0.12.3` | `0.12.3` | pending source package |
| `dagre-d3-es` | `7.0.14` | `7.0.14` | pending source package |
| `dayjs` | `^1.11.21` | `1.11.21` | pending source package |
| `dompurify` | `^3.3.3` (overridden) | `3.4.12` | pending source package |
| `es-toolkit` | `^1.45.1` | `1.45.1` | pending source package |
| `fastdom` | `1.0.12` | `1.0.12` | pending source package |
| `katex` | `^0.16.47` | `0.16.47` | pending source package |
| `khroma` | `^2.1.0` | `2.1.0` | pending source package |
| `marked` | `^16.3.0` | `16.3.0` | pending source package |
| `roughjs` | `^4.6.6` (patched) | `4.6.6` | pending source package and patch notice |
| `stylis` | `^4.3.6` | `4.3.6` | pending source package |
| `ts-dedent` | `^2.2.0` | `2.2.0` | pending source package |
| `uuid` | `^11.1.0 \|\| ^12 \|\| ^13 \|\| ^14.0.0` | `14.0.0` | pending source package |

## Original completion plan and remaining boundary

1. Verify the official Mermaid v11.17.2 release source at commit `dcb694d`
   and retain its lockfile without modifying the vendored runtime file.
2. Reconcile the 21 declared inputs above with the generated artifact/source map,
   including the workspace parser's exact release identity and transitive
   packages actually included in `dist/mermaid.min.js`.
3. For every resolved package, record package name, exact version, source
   revision/tarball hash, SPDX/licence expression, and the verbatim official
   licence/notice file in `compliance/licenses/`.
4. Recompute the vendored bundle hash and record the lockfile/source evidence
   alongside the inventory entry. A mismatch stops the audit.

The registry-package resolutions above were recorded from the official lockfile.
The new audit proves the workspace parser's published identity and records
generated mappings and package licence texts. It does not complete the deeper
prebundle attributions or installation of a complete notice inventory. No source
package or notice was fabricated, and the runtime bundle and pins remain unchanged.

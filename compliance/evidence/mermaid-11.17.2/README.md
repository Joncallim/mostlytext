# Mermaid shipped-module and licence evidence

> Current scoped attribution update — 3 November 2026: Cytoscape's own MIT text,
> the Gaëtan Renaudeau Bézier helper and jQuery-derived events now have separate
> distributed notices and mapped-code evidence in
> [the new checkpoint](../cytoscape-borrowed-attribution/README.md). The
> React-derived KaTeX notice was already addressed separately. Ralf Thenable,
> Framer spring, other embedded/generated helpers and the remaining full nested
> inventory stay open. Counts/status below describe the original dated evidence,
> not a current claim that those scoped notices are still absent.


> Later package-text integration — 3 November 2026: all 74 mapped package records
> now have complete selected distributed texts (including the existing Cytoscape
> notice). Two remain qualified content-matched references. Four Rough.js build
> input notices are also registered. See [the current package checkpoint](../mermaid-package-notices/README.md)
> and [source-build checkpoint](../nested-build-attribution/README.md). The original
> capture-only claims/counts below remain historical; embedded/generated code and
> origin ambiguities are not declared complete.


## Owner summary

The shipped Mermaid bundle is now connected to the official generated source
map, rather than only to a list of declared dependencies. The audit traces code
through the prebuilt parser and records exact package texts. This reveals more
work than the original 21-name inventory suggested: the bundle contains both
Lodash 4.17.23 and 4.18.1, and prebuilt libraries carry borrowed-code attributions
that their parent package's MIT label does not fully describe.

This is a **partial evidence checkpoint for #148 LC-01/LC-07**. It adds no editor
behavior and approves no dependency, distribution, legal status or release.
The inventory and generated distributed notices/SBOM are unchanged because the
complete nested attribution set has not been established. All eight release
checker entries remain open. The unresolved 484.814584/400 ms parser and
56.881709/50 ms editing-assist performance results are preserved; no benchmarks
were rerun for this work.

## Exact inputs

Work began on `fix/ci-timing-contracts` at
`40b25974fb367637cdec363d011f33b2d61c4a35`; master remained
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. The live issue body and all five
comments were read before this slice. Its governing obligations require actual
direct/transitive shipped content, verbatim notices, exact artifacts and negative
checks. Existing architecture, release hardening, audit and archive boundaries
were reconciled; this work introduces no application dependency or architecture.

| Input | SHA-256 |
| --- | --- |
| Shipped `mermaid.min.js` | `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8` |
| Official `mermaid-11.17.2.tgz` | `6ad2f42c3fc26bbf9e45cbb6d11898972573ea52b33a5f4ff51952899f950ffd` |
| Its `dist/mermaid.min.js.map` | `43cd977e8e0f351d6c47d31302c564f1c21fdc1e0be0d9e46370ee5e23cea004` |

The registry metadata and archive were fetched from
[npm Mermaid 11.17.2](https://registry.npmjs.org/mermaid/11.17.2).
Registry SHA-512 integrity and SHA-1 were verified before reading the archive.
The shipped bundle and root MIT text match its members byte for byte. The
publisher attestation names source commit
`dcb694ddb58dc5ad3502e7e903cac05fd812eac3`; its decoded statement is retained,
but **its signature was not independently verified**. The release lock was
downloaded at that full commit and preserved by hash. The verifier does not
parse that lock or use it as inclusion proof.

The earlier source-tree map URL was a 404; generated files are available in the
official npm archive. A guessed `patches/roughjs@4.6.6.patch` URL also returned
404 in this slice. The lock's actual path, `patches/roughjs.patch`, succeeded.
These failed fetches are retained in the evidence record.

## What is actually linked

The [machine mapping](module-notice-map.json) records source paths, generated
references, exact content hashes, archive member/map locations, registry/archive
hashes and selected package licence texts. It records:

- 1,151 sources with generated mappings in the official outer map. A mere entry
  in `sources` is not counted without a mapping.
- 32 prebuilt parser files that match the published `@mermaid-js/parser@1.2.1`
  archive exactly, including matching inner maps.
- 578 inner source records reached by composing outer parser positions with
  the greatest preceding mapping on the same generated line. Explicit unmapped
  segments and line boundaries are respected; they cannot inherit a prior source.
- 72 version records supported by versioned package input paths or byte-identical
  published parser chunks. Marked's 11 TypeScript files are absent as ordinary
  archive members but match `sourcesContent` in that exact package's maps.
- Two additional **content-matched candidate versions**, `vscode-uri@3.1.0`
  and `path-browserify@1.0.1`. All eight webpack source contents match vscode-uri's
  official maps; the path-browserify body also matches its own archive exactly.
  The automated verifier does not prove original build resolution from those
  versionless webpack paths or exclude identical contents in other releases.
  A `vscode-uri@3.1.0` input comment is visible in the matching parser chunk,
  but the generator deliberately makes the narrower automated claim.
- 74 selected package licence texts, each with exact archive location/hash.
  FastDom's complete MIT text is in its README; the recorded byte range is
  `[6431, 7525)`, SHA-256
  `50c0de64f5cd5e39859b43f7eca7f5843fb3c3d5ac7e34a453e27419ad51e08c`.
  The filename heuristic excludes `cytoscape/license-update.mjs`, which is a tool.

Seventy-seven candidate archives were downloaded and integrity-checked without
installation or package execution. Downloaded candidates that lack an inclusion
link are not promoted into the 74-record mapping. Khroma's MIT expression comes
from its actual licence text because its metadata omits a licence field.
DOMPurify's metadata offers `MPL-2.0 OR Apache-2.0`; the selected archive text is
Apache-2.0. This is not a claim that every alternative licence text was captured.

## Remaining evidence, not waived requirements

| Observed gap | Required completion evidence |
| --- | --- |
| 3,980 outer parser positions have no inner source association | Classify the unmapped/generated regions and any required helper attribution. Zero unclassified *named source paths* does not resolve these positions. |
| Cytoscape's matching prebundle identifies Engelschall's promises code, jQuery-derived events, Gaetan Renaudeau's Bezier generator and Framer/Koen Bok spring code | Resolve the exact embedded attribution/text obligations at the shipped revision. The existing bundle preserves short comments; those are not assumed to substitute for all required texts. |
| Rough.js is itself a prebundle with nested inputs | Establish its nested source/build linkage. The recorded patch changes only `bin/rough.d.ts`; its shipped runtime source is byte-identical to the unpatched archive. A lock entry is not proof that a nested dependency was emitted. |
| Other prebuilt units and webpack helpers | Finish a focused embedded-code/notice review; a matching parent artifact is not a complete transitive audit. |
| Candidate-version records and capture-only texts | Resolve original prebundle version provenance where needed; install the completed inventory, verbatim texts, generated notices and SBOM together, then verify the exact final artifact. |

This is the bounded stop point: further completion requires deeper source/build
attribution, not another package-range enumeration or an automatic inventory
status change. Publication and final signed-artifact inspection remain separate
owner-authorized phases. The recorded font KEEP decision is not reopened here.

The KaTeX `hyphenate` and `escape` attribution is addressed separately in
[`../katex-react-attribution/README.md`](../katex-react-attribution/README.md).
That scoped notice does not close the other Mermaid nested-code gaps above.

## Reproduction and negative controls

The raw evidence directory is
`/Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18/`.
It retains issue snapshots, official metadata/tarballs, maps, decoded analysis,
captured texts, download script, failed-fetch record and review/validation logs.
Each package record in the machine mapping gives its immutable-version retrieval
URL and expected hashes; archive data is never executed.

With that evidence directory, run from the repository root:

```sh
python3 compliance/tools/audit_mermaid_bundle.py \
  --evidence-dir /Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18 \
  --shipped-bundle MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js \
  --output /tmp/mermaid-module-notice-map.json
cmp compliance/evidence/mermaid-11.17.2/module-notice-map.json /tmp/mermaid-module-notice-map.json
python3 -m unittest discover -s compliance/tests
```

The replay validates registry integrity, package identity, bundle/map pairing,
source coordinates and exact source/notice links. It is deliberately offline
and does not change inventory status. The dependency-free source-map helper has
negative controls for a declared-but-unmapped source, malformed/out-of-bounds
mappings, changed bundle/archive/identity, duplicate generated coordinates,
unmapped composition regions, queries past the code, nonempty source roots and
UTF-16 supplementary characters. Notice controls preserve the README byte range
and exclude a licence-named source tool. All application source and pins remain
unchanged; this slice needs no app build or native desktop input.

Independent review verified the raw archive/source/text links and identified
two verifier defects plus an overly broad version-attribution claim. Those were
corrected before the checkpoint: duplicate coordinates fail, queries are bounded,
and the candidate-version claim is explicitly narrower. Final review and check
results are recorded in [VALIDATION.md](VALIDATION.md) and its machine-readable
[command/evidence record](validation.json). The full-suite fixture correction
and both initial failure causes are retained there.

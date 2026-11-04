# Complete tagged URI package reproduction — 4 November 2026

The entire published `vscode-uri` 3.1.0 npm archive reproduces **byte-for-byte**
from its upstream v3.1.0 tagged source and frozen Yarn lock. This includes all
17 package members, the 13 JavaScript/map/declaration files, npm tar metadata
and compressed bytes. The resulting SHA-256 is
`c6ec752d7a4858237389b23fb4d5ac05c2f1f606071cd212a9b54730e43cfc54`,
the same archive already bound by the [outer parser reproduction](../parser-runtime-reproduction/README.md).
Repeated packing and the separate portable recipe produce that same archive.

This establishes a complete technical reconstruction of the earlier nested
build, rather than comparing only four generated helper bodies. It does not
uniquely identify the publisher's historical execution, create signed publisher
provenance, grant rights or complete independent nested-code review. The registry
metadata has no gitHead or source attestation. Existing qualified attribution
labels, all notice/SBOM bytes, original reports, runtime and release predicates
remain unchanged.

## Exact input and output binding

| Input | Observed value |
|---|---|
| Upstream tagged source | [`edfdccd976efaf4bb8fdeca87e97c47257721729`](https://github.com/microsoft/vscode-uri/tree/edfdccd976efaf4bb8fdeca87e97c47257721729) |
| Source state | All 23 original file hashes unchanged after installation, both builds and packing. |
| Node | 20.19.0 Darwin ARM64, checked against the official archive checksum; upstream pipeline declares Node 20.x. |
| Package managers | Integrity-verified Yarn 1.22.22; npm 10.8.2 from that Node distribution. |
| Frozen build inputs | Webpack **5.94.0**, webpack-cli 5.1.4, TypeScript 5.2.2, ts-loader 9.4.4 and path-browserify **1.0.1**. |
| Build | Original TypeScript compilation followed by original production Webpack configuration. Install lifecycle scripts disabled, no source/manifest/lock edits. |
| Published payload | All 17 members and complete compressed archive equal. All 13 compiled JS/map/type members equal separately. |

The actual tagged lock selects 5.94.0, rather than the older 5.88.2 comparison
reference. The complete root MIT text in both compiler inputs is byte-identical
to the already distributed Webpack notice. Installed path-browserify's source
and complete licence match the existing mapped source/text hashes. All seven
URI source-map entries match their tagged TypeScript files exactly. The original
composed Mermaid map reaches 1,222 references to that same path-browserify body.

The [pinned manifest](manifest.json), [full receipt](reproduction.json),
[original source hash index](tagged-source-hashes.json) and
[source-map links](source-map-links.json) retain the concrete correspondence.
A source match does not show that every possible identical upstream version has
been excluded; no historical content-only record is silently rewritten.

## Actual refusal and restoration

Changing the real URI illegal-scheme error literal in `src/uri.ts` still compiles.
The same [13-member comparator](compare.py) then refuses five changed files:
both complete bundles/maps and the unbundled URI JavaScript member. Restoring
the exact original source returns all 13 matches. See
[the actual mutation](source-mutation-control.json) and
[restored proof](restored-source-proof.json). No assertion or threshold changed.

The offline verifier checks full membership, equality/count types, source and
toolchain identity, every pinned evidence file, the current shipped Mermaid
binding and distributed text. Controls reject altered archives, partial,
duplicate or substituted members, false equality, changed source/toolchain/text,
a successful replacement for the negative control, missing/tampered proof and
changed current runtime. These checks do not run upstream build tools in CI.

```sh
python3 compliance/tools/verify_uri_prebundle.py
python3 -m unittest compliance.tests.test_uri_prebundle -v
```

## Reproduce in an owned source directory

Obtain the immutable source and npm archive from their primary URLs above and
`https://registry.npmjs.org/vscode-uri/-/vscode-uri-3.1.0.tgz`. Verify the archive
against the registry SHA-512 and the pinned SHA-256. Obtain the exact Node and
Yarn distributions in [toolchain-proof.json](toolchain-proof.json), verify their
recorded checksum/integrity, and extract them without running install hooks.

Use an owned copy of the original tagged source and an output directory outside
that source. The [portable recipe](reproduce.py) checks all source hashes and
toolchain versions, performs frozen script-disabled installation, invokes only
the original compiler/production configuration and packs without publication:

```sh
python3 compliance/evidence/uri-prebundle-reproduction/reproduce.py \
  --source /path/to/owned/vscode-uri-source \
  --published /path/to/vscode-uri-3.1.0.tgz \
  --node /path/to/node-v20.19.0-darwin-arm64/bin/node \
  --yarn /path/to/yarn-1.22.22/package/bin/yarn.js \
  --output /path/to/owned-reproduction-output
```

The retained local capture also supports read-only replay:

```sh
python3 compliance/tools/verify_uri_prebundle.py \
  --replay-dir '/Volumes/Fast SSD/CORTANA-Builds/vscode-uri-prebundle-20261104'
```

Local build/install logs and unchanged raw archives are retained in that capture.
The broader [independent review packet](../../UPSTREAM_REVIEW_QUESTIONS.md),
source-offer authorization, final artifact, language and native gates remain open.

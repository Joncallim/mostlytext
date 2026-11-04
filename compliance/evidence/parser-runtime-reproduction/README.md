# Complete parser JavaScript reproduction — 4 November 2026

Current nested-build follow-up: [the entire vscode-uri 3.1.0 npm archive now reproduces byte-for-byte](../uri-prebundle-reproduction/README.md) from tagged source and its frozen Webpack 5.94.0/path-browserify 1.0.1 inputs. This is a separate technical reconstruction, without signed historical publisher-execution or independent rights clearance. The original outer receipt and scope below remain unchanged.

The parser's **96 JavaScript files and 96 source maps reproduce byte-for-byte**
from the source bound by [verified publisher provenance](../parser-publisher-provenance/README.md).
This supplies technical build correspondence for the outer parser compiler and
vscode-uri input. It is not an independent IP review, a full npm archive/type
rebuild, proof of every earlier nested build or final application acceptance.

[The receipt](reproduction.json) compares the complete published member set,
not just selected helpers. [The manifest](manifest.json) binds the receipt,
portable recipe, source index and controls. All 32 parser members reached by the
shipped Mermaid map and their maps are among those reproduced outputs. The
original content-only reports and their hashes remain unchanged.

| Input | Verified value |
|---|---|
| Publisher source | mermaid-js/mermaid at 293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4 |
| Published parser 1.2.1 archive SHA256 | 97eef1a4c37110e4836b6eb8dd6a348d989efb370a7672831df01042a7c323f4 |
| Node, from .node-version | 24.16.0; official platform archive checksum verified |
| Package manager | pnpm 10.30.3; archive matches the publisher packageManager SHA512 and registry integrity |
| Resolution | Original frozen pnpm lock; install scripts disabled; no input/pin edits |
| Outer compiler | esbuild 0.25.12, checked by the actual build wrapper |
| Parser generator/input | Langium 4.2.1; vscode-uri 3.1.0 |
| Platform | Local Darwin ARM64; publisher workflow declares Ubuntu |

All 1,753 original source files remain unchanged; [their full hash index](publisher-source-hashes.json)
also binds the previously captured publisher inputs. The added wrapper is local
build orchestration and is not bundled into any parser output.

## Scope and actual controls

The [portable recipe](reproduce-parser.mts) calls the real upstream Langium
generator and shared build configuration in the original three parser modes:
ESM, minified ESM and core ESM. It does not run the other package lanes or claim
the type/API-extractor prepack output. Its portable form was also executed and
returned the same complete output set.

Changing a real exported error literal in the owned upstream source still builds,
but [artifact comparison refuses six changed entry/map members](source-mutation-control.json).
Restoring the source and rebuilding again [matches all 192 members](restored-source-proof.json).
No validation/assertion was weakened. An initial attempt with the host's Node 26
failed inside the upstream schema validator; using the publisher's pinned Node 24
succeeds without patches or skipped schema validation. That failed attempt is
retained locally, not relabelled as a successful reproduction.

To reproduce, use an owned copy of the pinned upstream commit, the pinned Node
and integrity-verified pnpm. Keep the original manifest and lock. From that copy:

```sh
/path/to/node24 /path/to/pnpm/package/bin/pnpm.cjs install \
  --frozen-lockfile --ignore-scripts --filter '@mermaid-js/parser...' \
  --store-dir /path/to/owned-store
cp /path/to/this-packet/reproduce-parser.mts .mostlytext-reproduce-parser.mts
MERMAID_COVERAGE=false /path/to/node24 node_modules/tsx/dist/cli.mjs \
  .mostlytext-reproduce-parser.mts
```

Compare every .mjs and .mjs.map under packages/parser/dist against the pinned
published archive, including the complete name set. Offline CI checks the pinned
receipt, toolchain/source binding, all member pairs and shipped-map linkage; it
does not install or run upstream build tools. The source/dependency/runtime/IP
review and final artifact gates remain in MostlyText #14.

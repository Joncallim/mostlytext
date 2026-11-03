# Retained Webpack runtime MIT notice — 4 November 2026

Four complete Webpack runtime source bodies embedded through vscode-uri match a
generated **5.88.2 reference byte-for-byte**, without whitespace/comment/token
normalization. The composed shipped Mermaid/parser map reaches 125 references,
including 42 references to specific body operations. JS Foundation and other
contributors' complete authentic MIT text is now separately distributed.

This identifies a licensed matching reference, **not the original Webpack version**
or whole compiler package inclusion. vscode-uri 3.1.0 declares webpack ^5.88.2 as a
build input; that range alone does not prove its earlier exact resolution. The
outer parser's separate [complete reproduction](../parser-runtime-reproduction/README.md)
does not claim to recreate that earlier Webpack compilation.

[The mapping](mapping.json) binds the unchanged shipped bundle, parser archive
and chunk, generated reference and exact MIT text. [The reference map](reference-map.json)
comes from a small owned ESM/CommonJS fixture compiled with verified webpack 5.88.2
(Node 24.16.0); a reference build under ES5 target settings changes three helper
bodies and cannot satisfy this complete-source comparison. The original package
archive SHA256 is 4d92a947dbc855289a1a33a9a77dd9a2cf04606d721a74b18104de29aa1f8279,
registry gitHead 1f99ad6367f2b8a6ef17cce0e058f7a67fb7db18. The license is copied from
that archive, unchanged, SHA256 9068a8782d2fb4c6e432cfa25334efa56f722822180570802bf86e71b6003b1e.

| Complete source | Outer references | Body-operation references |
|---|---:|---:|
| Module cache/require bootstrap | 46 | 3 |
| Define property getters | 34 | 13 |
| hasOwnProperty shorthand | 12 | 12 |
| Mark namespace object | 33 | 14 |

Probes name return/defineProperty/hasOwnProperty operations, not comments or a
function name. Missing probes, changed bodies/notice/copyright, ambiguous input
maps and an unsupported exact-emitter/whole-package claim fail verification.

```sh
python3 compliance/tools/verify_webpack_runtime_notice.py
python3 compliance/tools/verify_webpack_runtime_notice.py \
  --evidence-dir /path/to/original-mermaid-capture \
  --reference-map compliance/evidence/webpack-parser-runtime/reference-map.json \
  --output /tmp/webpack-runtime-mapping.json
cmp compliance/evidence/webpack-parser-runtime/mapping.json /tmp/webpack-runtime-mapping.json
```

The owned reference fixture can be reproduced by copying reference-entry.js to
entry.js and reference-module.cjs to fixture.cjs, keeping reference-build.mjs and
copying reference-lock.yaml to pnpm-lock.yaml. Its package.json is simply
`{"private":true,"dependencies":{"webpack":"5.88.2"}}`. Install with the pinned
Node/pnpm using `--frozen-lockfile --ignore-scripts` and an owned store, then run
reference-build.mjs. dist-web/reference.js.map must match reference-map.json;
dist-es5 demonstrates the strict target-format difference. The source-map bodies
and exact package/license hashes are in [the reference build manifest](reference-build-manifest.json).
No reference fixture is an application dependency or part of the shipped runtime.

Ordinary CI is offline and uses Python's standard library. The actual reference
build, complete source comparison and raw source-map replay are retained in the
owned parser-reproduction-20261103 evidence directory. Unrelated embedded code,
earlier exact resolution, independent licence/runtime review, native and exact
signed-artifact/source-publication acceptance remain open. All six strict release
failures remain; no renderer or dependency is changed by this notice.

# Emitted parser runtime MIT notice — 3 November 2026

The shipped Mermaid outer map reaches an exact published parser chunk whose
unmapped preamble contains esbuild runtime helpers. Two complete bodies,
__commonJS and __export, match the licensed v0.27.7 reference after only narrowly
reviewed formatting normalization. Evan Wallace's complete MIT text is now a
separate distributed attribution. The original emitting compiler version remains
unresolved; no exact npm identity or whole-package inclusion is recorded.

The [mapping](mapping.json) pins the Mermaid bundle/map, parser archive/chunk,
reference source and license. The reference tag/npm gitHead agree on
2025c9ff6ab15ba6b0f9d074fd732250cc46e4a3; [runtime source](https://github.com/evanw/esbuild/blob/2025c9ff6ab15ba6b0f9d074fd732250cc46e4a3/internal/runtime/runtime.go)
and [license](https://github.com/evanw/esbuild/blob/2025c9ff6ab15ba6b0f9d074fd732250cc46e4a3/LICENSE.md)
are immutable references, not a claim that this version originally built parser
1.2.1. Multiple esbuild versions appear in the retained release lock; that lock
alone does not establish the prebundle's original compiler.

## Positive emitted-code proof

The selected parser member is dist/chunks/mermaid-parser.core/chunk-FOHPRMQF.mjs,
SHA-256 5c83305b04a62463567bdf6d82d9ba9dfc3795e516d8cc848e6981504af48068.
Its entire bytes match the mapped source. The __commonJS body has 32 outer
references, including 20 on the specific return-body probe; __export has 24,
including three on the actual export-loop probe. Neither comments, a mere source
list nor a function name alone counts as emitted-code proof.

The runtime preamble accounts for 452 of the original 3,980 outer parser positions
without inner source association. Their inner association is checked as absent;
this classifies that bounded generated region separately. The remaining 3,528
positions are not classified by this tool. The original dated source-map report
is unchanged. Generated mapping is provenance, not proof of every runtime path's
semantic reachability or complete nested attribution.

## Narrow comparison and replay

Whole raw inputs are independently pinned. Only these two string/regex-free
helper bodies are compared. The comparison removes comments, whitespace,
statement semicolons and a leading export keyword. Strings, regex/division,
escapes and a newline immediately after return are outside the admitted subset.
Raw body and token hashes are both recorded. This is neither a general JS parser
nor a general semantic-equivalence or copyright-licensing inference tool.

```sh
python3 compliance/tools/verify_esbuild_runtime_notice.py
python3 compliance/tools/verify_esbuild_runtime_notice.py \
  --evidence-dir /path/to/mermaid-148-40b25974-2026-10-18 \
  --reference /path/to/esbuild-runtime.go --output /tmp/runtime-mapping.json
cmp compliance/evidence/esbuild-parser-runtime/mapping.json /tmp/runtime-mapping.json
python3 -m unittest compliance.tests.test_esbuild_runtime_notice
```

Ordinary CI preserves the qualified identity and exact MIT text; full replay also
checks archive/map/source pairing, complete helper correspondence and body probes.
Controls reject operation/property changes, ambiguous/reversed boundaries,
unsupported syntax, altered notices and false exact-version promotion.
Captured reference files remain under
`/Volumes/Fast SSD/CORTANA-Builds/nested-notice-completion-20261103/upstream`.
No npm package, Go source, upstream build script or runtime helper is executed.

Other generated/embedded code, original compiler/candidate resolution and Framer
origin ambiguity remain open. All six strict failures stay in place. No native,
legal-clearance, signed-artifact or public source-offer approval is inferred.

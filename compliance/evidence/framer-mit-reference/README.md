# Framer spring: actual MIT reference and emitted code

The notice bundle now includes Koen Bok's complete MIT text from a verified
2014 Framer source revision. This is a conservative matching-source attribution,
like the existing Bézier/jQuery references. It does not establish the exact
original Framer input copied by Velocity/Cytoscape or complete independent
rights review. Older BSD-style reference evidence is preserved.

## A contemporary licensed source, not a guessed text

Commit [a41d843dc1371dd0cdc87d1fbbb3f833a5d24d58](https://github.com/koenbok/Framer/commit/a41d843dc1371dd0cdc87d1fbbb3f833a5d24d58)
on 24 June 2014 includes the actual [MIT LICENSE](https://github.com/koenbok/Framer/blob/a41d843dc1371dd0cdc87d1fbbb3f833a5d24d58/LICENSE),
Copyright (c) 2014 Koen Bok, and package.json's framerjs 3.0.0 / MIT declaration.
The full distributed text is a byte-for-byte copy, SHA256
298012b8b6c965d489221b5b79be5f77ca2027ec65d47a80b16b73812cb60a46.
No standalone license is assembled or inferred from a modern repository header.

The [SpringRK4Animator source](https://github.com/koenbok/Framer/blob/a41d843dc1371dd0cdc87d1fbbb3f833a5d24d58/framer/Animators/SpringRK4Animator.coffee#L57-L95)
contains four complete helpers. The full block equals the older 2.0
[BSD-style source reference](https://github.com/koenbok/Framer/blob/6fd264c787a410e47ea4d3e8e6e32d5f99d5ac8c/src/curves/spring.coffee#L9-L47)
after whitespace-only removal: 872 bytes, SHA256
91032f702c37375045a1df7fa857972f6f248b2a3f83fd35e662c7a9c2baed5d.
No operators, identifiers or comments are normalized. The [helper excerpt](helper-block.coffee)
is retained under the same [complete MIT text](../../licenses/cytoscape-framer-spring--MIT.txt).
[reference.json](reference.json) pins five complete source/package/license input
hashes and both exact source ranges. Earlier BSD evidence and the
[Velocity intermediary comparison](../framer-spring-history/README.md) remain
unchanged; finding this later MIT copy does not identify a unique original input.

## Actual shipped code

The unchanged Mermaid 11.17.2 bundle and exact official source map reach the
verified Cytoscape 3.34.0 dist member. Source lines 15112–15191 have 258 generated
references across 64 source lines. Four specific code probes have 7/9/9/8 generated
references: acceleration, derivative evaluation, RK4 integration and factory.
The [mapping receipt](mapping.json) records source/bundle/map/body hashes and
those actual probes. Comments or merely listed map sources cannot substitute.

Cytoscape expressly credits Framer/Koen under MIT. Its JavaScript adapts wrapper
behavior, inlines springEvaluateState and changes speed/dt parameters. The proof
does not claim complete compiled-JavaScript equality, identify which historical
revision was copied, or independently clear that adaptation's original grant.
Those questions remain in #14 and the [review packet](../../UPSTREAM_REVIEW_QUESTIONS.md).
No complete Framer package is claimed to ship or added as a runtime dependency.

## Replay and refusal controls

Raw Git objects, five source/terms/package inputs and comparison/control logs:
`/Volumes/Fast SSD/CORTANA-Builds/framer-spring-origin-20261104`.
The raw Mermaid/npm/map inputs remain in the preserved archive used by the
[earlier Cytoscape audit](../cytoscape-borrowed-attribution/README.md).
No source/package code is executed.

```sh
python3 compliance/tools/verify_framer_reference.py
python3 compliance/tools/verify_framer_reference.py \
  --evidence-dir /path/to/mermaid-11.17.2-evidence \
  --inputs /path/to/framer-reference-inputs --output /tmp/framer-mapping.json
cmp compliance/evidence/framer-mit-reference/mapping.json /tmp/framer-mapping.json
python3 -m unittest compliance.tests.test_framer_reference -v
```

Nine offline test methods reject incomplete/changed terms, missing author,
coherently rewritten notice/inventory, false exact-original claims, missing or
duplicate components, changed reference/mapping, arithmetic/identifier/comment
changes, missing generated probes, unreviewed code around the retained excerpt and missing proof. Six actual captured-input
mutations reject all five changed source/terms/package inputs plus substitution
of the older BSD text for this actual MIT reference. Full raw replay equals the
committed mapping exactly. An initial indentation-only positive control exposed
an overly literal block boundary; the reader was corrected and the original
failure retained, preserving strict body identity and actual input hashes.

No runtime, pin, old component/text, original evidence or release predicate is
removed. Inventory, generated notices and SBOM change together. All six existing
strict release failures remain. Source publication/anonymous retrieval, native
license-window and exact signed-artifact acceptance are unperformed.

## Built resource and final evidence review

The locked compile-only universal Release build succeeds. Its actual internal
bundle is MacDown2.app; the built notice is byte-identical to generated source,
496,371 bytes, SHA256 859b18af33f6b22973719404faee5e9c4a2f97bc8d463005eb86f4bc847e30bf,
below the unchanged 2 MiB reader limit. Artifact inventory passes and the exact
same six strict failure messages remain. Final package-pin check passes. No
product/native executable ran; this is not native licence-window acceptance.

Review also reproduced acceptance of extra code outside the reviewed helper
excerpt. Two actual assertions fail before the complete-file digest guard; the
corrected verifier pins the whole excerpt as well as checking its helper block.
The original failing log is retained. This changes only evidence validation, not
the notice, source map, runtime or any release predicate.

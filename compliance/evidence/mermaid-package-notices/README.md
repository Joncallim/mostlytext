# Distributed mapped Mermaid package texts — 3 November 2026

All 74 package records in the retained Mermaid source-map audit now have complete
selected texts in the distributed notice corpus. This adds 73 inventory records;
Cytoscape's own-code MIT record from PR23 is retained without duplication. The
originals come from integrity-checked npm archives; FastDom's complete README
license section uses the exact reviewed byte range. Both emitted Lodash versions
and multiple d3/layout versions remain distinct. No dependency or renderer byte
changes.

Two records, vscode-uri and path-browserify, remain content-matched references.
Their original build resolutions are not proved. Their names and version fields
say so in the generated notices/SBOM, and they have no exact npm package URL.
DOMPurify distributes its captured Apache-2.0 option, not an implied MPL source
offer. Full original license texts preserve their included author/notice wording;
this is not a claim that every per-file/borrowed-code copyright is audited.

The offline verifier pins the reviewed mapping digest and actual shipped bundle.
It replays the source-map audit on request, pins registry/archive hashes, verifies
package identities and copies only exact reviewed texts. Ordinary CI also checks
every installed component projection and text against the pinned map without
needing the raw capture. Missing/duplicate/extra records, altered texts and
promotion of a candidate to exact identity fail.

```sh
python3 compliance/tools/install_mermaid_notices.py \
  --evidence-dir /path/to/mermaid-148-40b25974-2026-10-18 --replay
python3 -m unittest compliance.tests.test_mermaid_notices
```

See [the original complete mapping](../mermaid-11.17.2/module-notice-map.json) for
source coordinates/archive members/hashes and [its evidence guide](../mermaid-11.17.2/README.md)
for capture retrieval. `--write` deliberately reinstalls the reviewed record set;
notices and SBOM must then be regenerated together. It cannot clear the strict
release item. Candidate origins, Ralf Thenable full-text linkage, Framer spring,
other nested/generated helpers and 3,980 unmapped parser positions remain open.
[Build-input notices](../nested-build-attribution/README.md) add bounded progress,
not complete Mermaid closure, independent provenance review or legal clearance.

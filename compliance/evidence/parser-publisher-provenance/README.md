# Verified parser publisher provenance

Current follow-up: [all 96 parser JavaScript files and 96 maps are now independently
reproduced locally](../parser-runtime-reproduction/README.md) with the pinned
toolchain. This original signed-publisher packet and its scope/manifest remain
unchanged; the separate reproduction does not claim type/prepack, earlier nested
build or independent IP review.

The exact published parser archive used by the shipped Mermaid map now has a
verified signed publisher record. It identifies the source commit and lets a
reviewer inspect the release workflow and dependency lock instead of guessing
versions from identical emitted code. This is publisher provenance, not an
independent rebuild, complete nested-code review or licence clearance.

## What was verified

The npm provenance bundle's archive subject matches parser 1.2.1 by SHA-512.
GitHub CLI verified its signature/transparency evidence, exact release-workflow
identity, source digest and hosted-runner requirement. A separate check of the
verified certificate enforces the GitHub token issuer, repository/owner numeric
identifiers, source URI/digest and runner environment; the current repository
identifiers were read back from GitHub. We do not infer issuer enforcement from
the CLI's returned wildcard issuer identity policy.

The archive also matches the existing SHA-256 and **all 32 mapped parser chunk
hashes** in [the shipped-source evidence](../mermaid-11.17.2/module-notice-map.json).
[The publisher run](https://github.com/mermaid-js/mermaid/actions/runs/32235658899)
completed successfully at source commit
`293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4`.

## What the pinned source declares

- The [release workflow](https://github.com/mermaid-js/mermaid/blob/293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4/.github/workflows/release.yml)
  uses a frozen dependency install. The root prepare/build scripts build the
  parser before the dependent Mermaid package; parser prepack handles type files.
- The [lock's Langium 4.2.1 dependency](https://github.com/mermaid-js/mermaid/blob/293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4/pnpm-lock.yaml#L20038)
  selects vscode-uri **3.1.0**.
- The [root compiler lock](https://github.com/mermaid-js/mermaid/blob/293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4/pnpm-lock.yaml#L142)
  selects esbuild **0.25.12**; the build entry imports that root compiler.
  This differs from the earlier v0.27.7 **comparison reference**, which was never
  claimed as the original compiler. The official 0.25.12 archive's complete MIT
  file is byte-identical to the already distributed runtime notice (SHA-256
  `b40ec5baec7bb34fa5b1c09521fa3cd52d5fad7adafed74932a2010d3612a681`).

These are declared publisher-build inputs tied to the signed package. They do
not independently reproduce the compiler execution. The older content-only
mapper is preserved as its original scoped result; its candidate labels are not
silently rewritten into independent rebuild claims. The path-browserify code
inside the already prebundled vscode-uri package still needs its own original
build-resolution review. Merely finding a path-browserify version elsewhere in
the outer lock would not prove that earlier compilation.

## Replay and controls

[The manifest](manifest.json) pins the bundle, archive, source files and licence
comparison. [The receipt](verification.json) records the enforced certificate
fields and five real refused controls: wrong workflow, source commit or issuer,
altered archive and altered signed payload. A successful CLI exit alone is not
our complete acceptance policy.

```sh
gh attestation verify parser-1.2.1.tgz \
  --bundle compliance/evidence/parser-publisher-provenance/attestation.bundle.json \
  --repo mermaid-js/mermaid --digest-alg sha512 --deny-self-hosted-runners \
  --cert-identity 'https://github.com/mermaid-js/mermaid/.github/workflows/release.yml@refs/heads/master' \
  --cert-oidc-issuer https://token.actions.githubusercontent.com \
  --source-digest 293b1c153a6f94c3a4a1d9cd5eae4dde609f1ec4 --format json > verified.json
```

Then compare the output's `verificationResult.signature.certificate` fields to
`verification.json`'s certificate policy, require a verified timestamp, and check
the archive subject digest. The numeric repository/owner identifiers must also
match the current primary repository before treating its name as current.
The command may fetch public trust roots; it creates no signing key.

No upstream build/package/helper was executed. Runtime bytes, selected licence
texts, inventory, notices, the 3,528 remaining parser review positions and all six
strict release predicates remain unchanged. The [review packet](../../UPSTREAM_REVIEW_QUESTIONS.md)
now separates these new publisher facts from the remaining independent questions.

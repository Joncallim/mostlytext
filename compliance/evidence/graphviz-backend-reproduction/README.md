# Complete Graphviz backend reproduction

The complete 1,173,021-byte `package/lib/backend.js` from `@viz-js/viz` 3.30.0
reproduces byte for byte from the recorded Graphviz 16.0.0, Expat 2.8.4 and Viz.js
source recipe, using the recorded Linux AMD64 compiler image. Its SHA-256 is
`d2d18f488ffbf12fd3ae68d3899d6911051b9bfc3b4240eebe9883ca17d58903`.
No JavaScript or WebAssembly output was loaded to establish this comparison.

The first successful [hosted run41819062875](https://github.com/Joncallim/mostlytext/actions/runs/41819062875)
used source `24f21198b1c00bb30356da1e8ae891a04a479857`. Its [actual receipt](result.json)
binds four complete input archives, five context files, original/derived recipe,
preparer and complete expected/rebuilt output. The Docker engine's captured image
configuration ID is `f8b9ec6ea64ccb381d9a9553146fa265eeb72b8a5283d582bb6f492a1f6385f0`,
with Linux/AMD64, matching the [earlier complete image graph](../viz-compiler-image/README.md).
Raw run/artifact ZIPs, image inspection, full build log and local preparation are
retained under `/Volumes/Fast SSD/CORTANA-Builds/graphviz-backend-rebuild-20261104`.
The complete raw receipt has an offline byte pin in the verifier.

## Recipe and execution boundary

The [original 2,048-byte Dockerfile](upstream-Dockerfile) is from Viz.js commit
`99da545270e6e7b127a5c7ba65974b8a604a6358`, under its complete
[upstream MIT text](UPSTREAM-LICENSE.txt). Both hashes match the original
[source audit](../viz-js-3.30.0/source-audit.json). The derived recipe changes
exactly four lines: both base tags become the recorded platform child digest,
and both quoted remote ADD instructions become COPY of their verified tarballs.
All working directories, two fresh stages, configure/make/link flags and the
empty DEBUG default remain intact. No output normalization or guessed build
input was used. Context sources and archive bytes are checked again at comparison.

Only an ephemeral hosted Linux runner executes the compiler. It receives the
five-file context, with no owner data, secrets/SSH forwarding or build-container
host mounts. RUN network and shared build cache are disabled. The workflow has
read-only repository permission, does not persist checkout credentials and has
a 45-minute limit. Artifacts contain only JSON receipts and logs. No generated
backend, source-review archive or application binary is uploaded as an artifact.
No local Docker/OS setup or owner-account native application execution occurs.

## Replay

Ordinary compliance controls stay offline and do not execute upstream code:

```sh
python3 compliance/tools/verify_graphviz_rebuild.py
python3 -m unittest compliance.tests.test_graphviz_rebuild -v
```

Prepare the retained public inputs into a new owned directory outside the checkout:

```sh
python3 compliance/tools/rebuild_graphviz_backend.py prepare \
  --inputs /path/to/graphviz-inputs --output /path/to/new-owned-preparation
```

The explicit `--download` option instead downloads the four pinned archives to a
new input directory. Both modes reject changed archives and refuse output reuse.
The path-scoped/manual `Graphviz backend reproduction` workflow performs the
container build and full comparison. To run it after merge:

```sh
gh workflow run graphviz-reproduction.yml --repo Joncallim/mostlytext --ref main
```

Comparison records both complete-file identities and fails on any byte difference.
Refusal controls cover changed archives/flags/context/receipts, selected duplicate,
linked, oversized or unsafe members, protected scratch, hosted identity and output
differences. Current shipped renderer bytes remain bound to the prior npm audit.

## Failed-first evidence and limits

The first local preparer refused because its literal match omitted the original
ADD URL quotes. The failed owned context is retained; exact quoted matching was
corrected before hosted execution. Initial local controls passed, then separate
[Compliance run41819062823](https://github.com/Joncallim/mostlytext/actions/runs/41819062823)
found that a new fixture inherited a GitHub run ID without its rebuild-only source
head. This does not affect the successful compiler result. Its raw failure is
retained; fixture environment isolation and explicit identity controls correct it
before merge. Green reruns do not replace these first observations.

This is an independently observed backend rebuild, not a fresh npm/Rollup wrapper
build, unique historical-input proof, publisher signature verification, exhaustive
linked-object/per-file rights review or independent legal clearance. The earlier
source audit remains immutable; its historical "no independent rebuild" describes
that original checkpoint. Complete corresponding-source approval, runtime/grant
review, separately authorized source publication/anonymous retrieval, native
acceptance and final signed-artifact verification remain open. No inventory,
notice/SBOM, runtime, pin, source-offer state or strict release predicate changes.

# Complete shipped Viz.js renderer reproduction

All five generated runtime files in `@viz-js/viz` 3.30.0 reproduce byte for byte
from the recorded Graphviz/Expat/Viz.js source, compiler image, frozen npm lock
and an explicit Node reference. This includes the exact `viz-global.js` bundled
with MostlyText. [Hosted run41822550855](https://github.com/Joncallim/mostlytext/actions/runs/41822550855)
at `d8134ba0340896a47eaceb2caac0b0a060adc863` passed the complete comparison.
The [actual receipt](result.json) preserves every full hash and build input.

| Generated file | Bytes | SHA-256 prefix |
|---|---:|---|
| lib/backend.js | 1,173,021 | d2d18f488ffbf12f |
| lib/metadata.js | 390 | 93aaf62515bbabe8 |
| dist/viz.js | 1,184,246 | fef725087058053e |
| dist/viz.cjs | 1,184,659 | 3a3e781ad1247322 |
| dist/viz-global.js | 1,324,675 | c857641af952c8f8 |

No minifier/source patch, output normalization or changed compiler/link flag was
used. The original [backend recipe and proof](../graphviz-backend-reproduction/README.md)
remain unchanged. The new stage uses upstream metadata generation and make,
including its original Rollup/Babel/Terser configuration. The frozen
[package-lock.json](package-lock.json), SHA-256
`7be731a17bc7de9ce8a69577d8516e3138e77c8e16e3f3babca1e4e37b9671f8`,
is checked before and after installation/build. These copied upstream reference
inputs retain the [Viz.js upstream MIT terms](../graphviz-backend-reproduction/UPSTREAM-LICENSE.txt).

## Fully offline execution from verified inputs

The lock's 546 resolved registry records reduce to 523 distinct tarball objects,
totalling 290,577,307 bytes. All have SHA-512 Subresource Integrity records. The
runner downloads only their fixed HTTPS registry URLs, verifies each integrity,
then copies the verified objects into an isolated build context. A complete
[dependency receipt](dependencies.json) records every identity and byte count;
its independent byte pin and frozen-lock plan are checked offline. Downloads have
eight workers, a 32 MiB individual bound and a 512 MiB total bound, with exclusive
new files and no credential/source execution.

Inside the container, npm's cache is populated from those local tarballs with
scripts disabled, then upstream clean-install runs with `--offline` and the
explicit cache. Every build RUN uses network=none. Metadata generation does
load the rebuilt backend inside this disposable hosted Linux container; no
upstream runtime or product is executed on the local Mac. Checkout has read-only
permission and no persisted credential; build containers receive no owner data,
secret/SSH forwarding or host-directory/socket mounts. No shared build cache is
used. Hosted artifacts retain only JSON receipts and logs, with a 45-minute bound.
No JS/WASM output, source-review archive or application binary is uploaded.

Actual engine inspection matches the recorded Linux AMD64 config
`f8b9ec6ea64ccb381d9a9553146fa265eeb72b8a5283d582bb6f492a1f6385f0`.
Raw run/artifact ZIPs, failed-first evidence, all tarballs and preparation/build
receipts are retained at `/Volumes/Fast SSD/CORTANA-Builds/viz-renderer-rebuild-20261104`.

## Tool versions are reference facts

The original [captured npm publisher metadata](npm-publisher.json) says Node
24.19.0 and npm 12.0.2. Its complete bytes match the original audit's download
identity. The upstream build workflow specifies Node `24.x`; the separate
publication step upgrades npm globally. Those records do not identify a unique
historical build toolchain.

This reproduction uses the official Node 24.19.0 Linux AMD64 archive, pinned by
the captured [official checksum list](SHASUMS256.txt) and
[reference record](node-reference.json). Measured container versions are
**Node v24.19.0 and npm 11.17.0**, the npm bundled with that Node archive. Preserve
that difference. All five complete output files match with those measured tools;
no upgrade or guessed historical npm version is needed to force equality.

## Replay and refusal controls

Ordinary CI checks only captured data/source and performs no downloads or execution:

```sh
python3 compliance/tools/verify_viz_renderer.py
python3 -m unittest compliance.tests.test_viz_renderer_rebuild compliance.tests.test_viz_renderer_receipt -v
```

Replay all actual retained tarball integrity/object checks without executing them:

```sh
python3 compliance/tools/verify_viz_renderer.py --packages /path/to/retained-offline-packages
```

Prepare a fresh context from the retained source, official Node and package objects:

```sh
python3 compliance/tools/rebuild_viz_renderer.py prepare \
  --inputs /path/to/graphviz-inputs --node /path/to/node-v24.19.0-linux-x64.tar.xz \
  --packages /path/to/retained-offline-packages --output /path/to/new-owned-preparation
```

The explicit `fetch-packages --inputs … --packages …` command downloads and
verifies a fresh tarball cache. `prepare --download` downloads all pinned inputs
into new directories/files. The path-scoped/manual `Complete Viz.js renderer
reproduction` workflow performs the isolated compilation and comparison. After
merge, `gh workflow run viz-renderer-reproduction.yml --repo Joncallim/mostlytext
--ref main` starts a replay. A missing input or any complete-file difference fails.

Fifteen offline methods cover source/Node/lock/context identity, changed/missing/
extra/linked tarballs and generated outputs, cache integrity/bounds, actual shipped
resource, all five output claims, raw receipt pins and coherent false metadata.
The existing backend/image controls continue to run separately. Historical
receipts are never retargeted to newer source.

## Failed-first evidence and remaining obligations

[First run41821191927](https://github.com/Joncallim/mostlytext/actions/runs/41821191927)
at `60a48b1d` fails resolving registry.npmjs.org during installation; no wrapper
comparison was reached. The architecture is reconciled before implementing the
offline cache. Docker documents that
[`RUN --network=default`](https://docs.docker.com/reference/dockerfile/#run---networkdefault)
uses the build's default network; it did not escape build-level network=none.
Keep that failure and the successful offline build as distinct observations.
The build retains frozen-package deprecation/Browserslist messages; dependency
updates would invalidate this historical-input reproduction and are not applied.

This completes technical correspondence of every generated runtime file, including
the shipped renderer. It does not reproduce the entire npm archive/provenance,
attest unique historical publisher execution, clear exhaustive linked-code/per-file
or independent rights review, approve complete corresponding source, authorize
source publication/anonymous retrieval, or establish native/exact signed-artifact
acceptance. Product/runtime, inventory, distributed notices/SBOM, pins, source-offer
state, release guards and all six strict failure messages remain unchanged.

# Graphviz source inputs and Expat attribution (#148, LC-02)

> Current preparation update — 3 November 2026: the
> [local source-review assembler](../graphviz-source-review/README.md) now packages
> the retained inputs. [Bison exception and Emscripten/musl root notices](../nested-build-attribution/README.md)
> are distributed conservatively. Earlier seven-failure counts are historical; the
> current count remains six. This does not complete compiler/runtime attribution,
> independent corresponding-source review, public source availability or signing.


The unchanged diagram renderer includes Expat 2.8.4, whose MIT notice was
missing from the generated notice bundle. This change records that embedded
component, adds its exact upstream `COPYING` text, and replaces the wrapper
and Graphviz licence copies with the texts from their identified source
revisions. Diagram rendering and all dependency pins remain unchanged.

The former wrapper notice used a 2014–2018 copyright line absent from this
release's `LICENSE`. The former Graphviz licence file appended GPL-2.0 and
Classpath-exception text absent from Graphviz 16.0.0's `COPYING`. These copies
are now byte-identical to the relevant upstream files. This does not assert
that every source file or compiler runtime has been audited; that remains an
explicit release finding. Previous copies remain in Git history and the local
evidence archive.

## What was verified

On 2026-10-19, against the renderer in candidate `ad79f2773f2cbaf8bb78bdb796b1d11b411be79b`:

- The downloaded `@viz-js/viz@3.30.0` tarball matches npm's SHA-512 integrity
  value. Its `dist/viz-global.js` equals the shipped 1,324,675-byte file,
  SHA-256 `c857641af952c8f82ac7243917f8563959046e5cfc44d7e84eff9a2b470f5eab`.
- npm's `gitHead` and the `release-viz-3.30.0` tag name commit
  `99da545270e6e7b127a5c7ba65974b8a604a6358`. All published wrapper sources
  and type declarations match the source archive at that commit.
- The npm package contains `lib/provenance.json`. Its subject digest equals
  the actual `lib/backend.js` digest; its source revision is the same commit.
  Its Graphviz and Expat input digests equal the independently downloaded
  gzip archives. Publisher release metadata reports the same archive digests.
- The source Dockerfile statically builds Expat 2.8.4 and explicitly links
  `-lexpat` with Graphviz. The build record also names the resolved
  `emscripten/emsdk:5.0.7` linux/amd64 image digest. These are publisher build
  records, not a locally reproduced build or cryptographically verified
  attestation.
- Expat's `COPYING`, Viz.js's `LICENSE` and Graphviz's `COPYING` are copied
  verbatim and checked against their archives. The ordinary inventory gate
  protects their digests and generated notice/SBOM consistency.

## Nested Graphviz attributions (2026-10-20)

The same verified Graphviz 16.0.0 source archive contains a separate
`lib/rbtree/LICENSE` that was absent from MostlyText's notices. The Viz.js
Dockerfile links `-lgvplugin_neato_layout`; that plugin's `Makefile.am` links
`librbtree_C.la` and `libneatogen_C.la`; `lib/neatogen/overlap.c` calls
`RBTreeCreate`, `RBTreeInsert` and `RBTreeDestroy`; and the tree library's
`Makefile.am` builds `red_black_tree.c`. These files and their digests are
checked in [source-audit.json](source-audit.json). The exact 1,048-byte
[`lib/rbtree/LICENSE`](https://gitlab.com/graphviz/graphviz/-/blob/06fff22d8e1a2aead6de0042e5e5ec2f7749be29/lib/rbtree/LICENSE)
is distributed as `compliance/licenses/graphviz-rbtree--LICENSE.txt` and in
the generated notices. It names Emin Martinian in a non-endorsement condition
but contains no explicit copyright line or stated SPDX identifier, so the
inventory uses a custom `LicenseRef-Graphviz-RBTree` and preserves the text
verbatim.

This establishes a source-build linkage path, not an independently reproduced
WebAssembly binary or proof that every library object survived linker removal.

The same source-chain review found two more notices in the Graphviz archive.
`lib/common/ellipse.c` credits Luc Maisonobe's derived ellipse code under a
separate three-clause notice alongside Graphviz's EPL-2.0; Viz.js links
`libgvc`, which links `libcommon`, whose source list includes that file.
`lib/neatogen/randomkit.c` and `.h` carry BSD-style and MIT notices for the
Mersenne Twister and Random kit routines; the Neato plugin links `libneatogen`,
whose source list includes `randomkit.c`. The exact opening comment blocks
are checked against the upstream archive and distributed verbatim in the
generated notices. [source-audit.json](source-audit.json) records source and
notice digests. These paths likewise establish conservative source-build
attribution, not exact linker retention in the published WebAssembly.

The Graphviz and Emscripten runtime audit remains open, including
classification of generated Bison parser skeletons and their stated special
exception. No renderer byte, dependency pin, or source-offer status changed.

## Retained inputs and repeatable check

[downloads.json](downloads.json) records the original URLs, byte sizes and
SHA-256 digests. [source-audit.json](source-audit.json) records source commits,
build-file hashes, matching wrapper files and the backend's publisher input
digests. It intentionally distinguishes these checks from build reproduction.

The source archives and raw API records are retained locally under
`/Users/jonathanlim/GitHub/_cleanup-archive/issue-convergence-6ed89086-2026-10-19/graphviz-inputs/`.
They have not been published as MostlyText's corresponding-source offer.
Download the named inputs to a local directory and run:

```sh
python3 compliance/evidence/viz-js-3.30.0/audit-source-inputs.py --inputs /path/to/graphviz-inputs
```

The checker reads tar members without extracting or executing them and fails
on a changed archive, mismatched bundle/source/build record or licence copy.
No npm install, Docker build or upstream script is executed. The two additional
Expat ref records come from GitHub's
`repos/libexpat/libexpat/git/ref/tags/R_2_8_4` and
`repos/libexpat/libexpat/git/tags/6dd46f3d0fcaeda0af6d00fd496acb8fe96b900d`
API endpoints. The annotated tag resolves to
`12cf0b1f25f026a022fe728ad8f7e3d017285b80`.

## Remaining gates

The seven strict release findings remain. For Graphviz, exact upstream inputs
are now retained, but the complete corresponding-source package still needs
assembly/review, owner-authorized source-only publication and anonymous
retrieval. The remaining embedded Graphviz/Emscripten runtime attribution
audit is not replaced by the direct linker list. Source-offer status remains
`planned`; no release clearance, signature validation or signed-artifact
verification is claimed. No component version or renderer byte changed.

The same correction also registers only XcodeGen's generated app
`MacDown2/MacDown2/Info.plist` as first-party metadata. The regression rejects
an adjacent unregistered plist. The generated file is distributed app metadata,
not an exclusion from scanning; Git ignore rules still grant no exemption.

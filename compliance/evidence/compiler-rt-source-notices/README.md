# Compiler-rt root attribution for the Viz.js build

Current image follow-up: [the recorded compiler image graph and selected files](../viz-compiler-image/README.md)
are now independently digest-checked without executing the image. The full root
licence, credits and three link/driver sources match this reference exactly; the
image's 5.0.7 release marker deliberately differs from this Git reference's
5.0.7-git marker. This original packet is preserved. Linked-object, per-file,
independent rights/source and final release review remain separate.

The recorded Viz.js publisher build names `emscripten/emsdk:5.0.7` and its
linux/amd64 image digest. The existing immutable Emscripten source reference is
`263db4cffa6f9fc2ec514a70abac81362ea41849` (source version `5.0.7-git`).
Its normal `get_libs_to_link` path adds `libcompiler_rt`; `tools/link.py`
consumes the calculated libraries, and the retained publisher Dockerfile invokes
ordinary `emcc` without `-nostdlib` or `-nodefaultlibs`.

The complete [compiler-rt root licence](https://github.com/emscripten-core/emscripten/blob/263db4cffa6f9fc2ec514a70abac81362ea41849/system/lib/compiler-rt/LICENSE.TXT)
and referenced `CREDITS.TXT` were missing from MostlyText's notice corpus.
Both exact files are now distributed. The licence contains Apache-2.0 with LLVM
exceptions plus its included legacy University of Illinois/NCSA and MIT sections;
the complete text is retained under a qualified custom inventory identifier.
The credits are upstream's explicitly partial contributor list, not an assertion
that these are all authors of the compiler/runtime or shipped output.

The [manifest](manifest.json) binds six full input hashes and Git blob identities,
three byte-offset source anchors, the publisher image/build-source record and the
unchanged shipped renderer. The raw immutable-commit files and complete GitHub tree
response are retained at `CORTANA-Builds/emscripten-runtime-20261104`; every raw
file's Git blob SHA-1 was checked against that tree in addition to SHA-256.
The source files and compiler image were not executed.

```sh
python3 compliance/tools/verify_compiler_rt_notices.py
python3 compliance/tools/verify_compiler_rt_notices.py --inputs /path/to/retained-inputs
python3 -m unittest compliance.tests.test_compiler_rt_notices
```

The optional raw-input replay checks the complete parent bytes, blob identities
and exact anchor offsets. The offline installed check protects the captured
manifest, complete root/credit texts, conservative inventory, generated notice
corpus and existing publisher/renderer binding. Tests remove legacy conditions,
exceptions and contributor credits, attempt coherent rewrites/overclaims and
change the compiler-image binding. No network access is needed in Compliance.

This is conservative source-build attribution. It does not establish that every
selected runtime object survived linking, uniquely identify the complete build
image/sysroot from a tag reference, or supply an independent WASM rebuild/per-file
licence audit. libc++/libunwind were not added merely because their sources exist;
their conditional selection and any retained-code obligations remain review work.
No version, renderer byte, dependency pin or source-offer status changed. The
refreshed [Graphviz review package](../graphviz-source-review/README.md) is still
unapproved and unpublished; source publication, independent rights/source review,
native UI and exact signed-artifact acceptance remain separate gates.

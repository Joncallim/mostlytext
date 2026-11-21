# D2 cold Quick Look budget: streaming compilation trial

## Owner summary

The installed Quick Look provider still shows source for a cold D2 diagram because the existing D2 engine misses its bounded publication window. This trial changes only how the same reviewed WebAssembly bytes are prepared and handed to the same worker. If it does not produce a measured cold latency gain and a real rendered Finder reply within the unchanged deadline, it will not become a product PR.

## Baseline and hypothesis

Current main is `f11c75c549cf786972e2a372a84fd0f4501dd5e4`. The retained [installed Finder run](https://github.com/Joncallim/mostlytext/actions/runs/44927075381) returned a 358-byte source fallback after starting D2 with 2.744 seconds left. The subsequent [Release renderer run](https://github.com/Joncallim/mostlytext/actions/runs/44930319994) measured 2.681 seconds from ordinary D2 input to SVG on its separate host. These are different scopes and neither is a Quick Look pass.

The current split browser loader first reads the entire 23,704,068-byte WASM resource into an ArrayBuffer, clones it to the compute worker, and compiles it there. The trial uses `WebAssembly.compileStreaming` on the resource response and sends the compiled module to that worker. This may overlap transfer and compilation; it may also fail if WebKit does not support this route for the private bundled scheme. The worker still instantiates the exact same module with the same Go imports. The fixed resource allowlist, CSP, source/output bounds, fallback, three-second child deadline and existing Quick Look reply ownership do not change.

The first [Release run](https://github.com/Joncallim/mostlytext/actions/runs/44947760225) compiled but refused ordinary D2 and both 256-edge controls. A branch-only diagnostic [run](https://github.com/Joncallim/mostlytext/actions/runs/44949226058) captured the exact preparation error: `Unexpected response MIME type. Expected 'application/wasm'`. The revised trial wraps the same private-scheme response body in a `Response` with that explicit content type before streaming compilation. The first failure remains negative evidence; it is not a latency measurement.

## Evidence and stop conditions

`compliance/evidence/d2-runtime-resource/stream_d2_browser.mjs` refuses any split-browser input other than the exact reviewed SHA-256 and makes two exact replacements. The 23,704,068-byte WASM remains byte-identical. First qualify actual D2 rendering, SVG ownership and resource denial through the existing hosted Release diagram workflow. Compare its cold timing and helper memory against the retained baseline, preserving any first failure. If supported and materially faster, activate D2 in the existing bounded Quick Look child and require a real installed Finder SVG plus previous math/Graphviz/Mermaid/fallback cases on the same tree. If the renderer fails or the Finder reply still falls back, remove the experiment from the merge path; no limit is raised and no source fallback is called static D2 output.

This experiment does not address #14's rights/source-publication decisions or substitute for the deferred protected native checkpoint.

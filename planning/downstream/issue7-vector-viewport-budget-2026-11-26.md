# Bound D2 and Graphviz vector canvases

## Owner summary

Very large diagrams can produce a small SVG file whose declared canvas is
enormous. Preview then hands that canvas to AppKit, and Export can embed it in
another document. This change refuses that generated result. Preview shows its
existing render error; Export and Quick Look preserve the authored fence through
their existing per-fence fallback. Ordinary diagrams and authored colors keep
their current behavior.

The implementation starts from `main` `da65d379e3aa29d9e9c0049ddb23cdc97a0fb72d`.
Mermaid's SVG-only path already caps a vector viewBox at 65,536 units per side
and 64 Mi units of area. D2 and Graphviz validated positive, finite viewBox
dimensions but had no maximum. Their retained 18 November Release probes show
valid D2 256-edge chain/star canvases at 282 × 42,764 and 34,772 × 434 and
Graphviz 128-edge wide/tall canvases at 11,929 × 44 and 73 × 9,260. All are
below the shared vector ceiling. A 2 MiB SVG byte cap cannot bound those
dimensions.

## Scope and behavior

- Apply Mermaid's existing vector-only side and area ceiling inside the bundled
  D2 and Graphviz glue immediately after viewBox parsing, before theme rewrites,
  canvas insertion and serialization. The diagram runtime and its offline
  WebKit authority stay unchanged.
- Keep finite/positive validation and the existing 64 KiB source, 2 MiB output
  and five-second render limits. An excessive viewport is a renderer resource
  refusal, not an authored syntax error. Preview keeps its error state; the
  Export and Quick Look contribution paths preserve source and continue
  rendering independent fences. Graphviz's failure classifier recognizes the
  exact new internal refusal instead of blaming the authored DOT.
- Test the actual bundled WebKit scripts with tiny SVG fixtures at the side
  and area boundaries and immediately beyond them. Existing real renderer and
  composition suites qualify ordinary output and fallback downstream. The
  Graphviz classifier regression failed on the baseline implementation as
  `invalidSyntax` and passed after the resource-failure mapping.

This is a bounded output-consumption policy. It does **not** cap D2/Graphviz
WASM memory during compilation, establish an end-to-end Quick Look latency
budget, or complete issue #7's empirical Release calibration. Those original
criteria remain open pending repeated cold/warm Release measurements, helper
memory attribution, cancellation and mixed-renderer checks. The protected
installed-app checkpoint remains deferred.

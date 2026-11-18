# D2 layout failure in Release diagram calibration

The [hosted Release source-budget run 44122298387](https://github.com/Joncallim/mostlytext/actions/runs/44122298387)
used pinned D2 0.1.33 on macOS 26.7.2. A 512-edge linear chain compiled but
its Dagre layout raised a JavaScript maximum-call-stack error after 0.536 s.
The product renderer reported this as `invalidSyntax`, which incorrectly
attributes a runtime/layout capacity failure to the authored D2 source.
The same run rendered 256-edge linear and star graphs in 3.131 s and 2.886 s
including cold initialization. A 512-edge Graphviz chain and 128-edge Mermaid
graph rendered in their separate processes. These are observed shapes, not
a universal graph-size threshold or a reason to raise the existing timeout.

The harness now identifies whether a failure occurred during configuration,
compilation or rendering. The Swift renderer retains `invalidSyntax` for D2
compile failures and maps render/layout failures to `rendererUnavailable`.
The contribution layer already keeps authored fences when rendering fails;
the new real-engine regression checks the distinction on the pinned chain.
No D2 engine bytes or renderer timeout/output ceiling change in this slice.

The same Release probe records test-host and newly observed WebKit-helper
memory separately, but its helper attribution is provisional. It does not
calibrate all cold/warm, wide/tall, cancellation, memory and mixed-renderer
cases required by [#7](https://github.com/Joncallim/mostlytext/issues/7).
Quick Look's sandboxed static-diagram path, final Release candidate and
installed Finder behavior remain open.

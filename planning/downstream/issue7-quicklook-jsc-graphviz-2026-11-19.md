# Static Graphviz in the bounded Quick Look child

## Owner summary

Finder currently shows a Graphviz code fence as source. The normal export renderer uses WebKit, but the actual sandbox-only Quick Look worker could not start that renderer. Keep the existing complete source fallback and the same three-second parent deadline. Test whether the bundled Viz.js engine can produce a static SVG through public JavaScriptCore inside the short-lived child, without network or new file authority. If it cannot, leave Graphviz as authored source and do not merge this candidate.

## Baseline and observed failure

The implementation baseline is `main` `dbbcabfff0dd0ca08c62e8553ae1686199590562`. The normal worker already renders static math, with an immutable source reply marked before derived work. The selected file is read once from its descriptor; the child receives no path or directory grant. `QuickLookSource` and `ExportService` validate generated fragments and preserve source on rejection. The bundled Graphviz resource is `viz-global.js` (1,324,675 bytes, SHA-256 `c857641af952c8f82ac7243917f8563959046e5cfc44d7e84eff9a2b470f5eab`).

A direct WebKit contributor candidate compiled locally, but genuine installed-provider [run 44414497906](https://github.com/Joncallim/mostlytext/actions/runs/44414497906) failed its new Graphviz assertion. The screenshot and accessibility tree show the authored fence. In [run 44418142505](https://github.com/Joncallim/mostlytext/actions/runs/44418142505), the worker recorded two `rendererUnavailable` results in 0.211 and 0.433 seconds, with zero accepted content and normal renderer shutdown. Existing math/GFM/encoding controls preceded the failure. This does not by itself identify the OS process that refused WebKit. Earlier private provider evidence in `quicklook-evidence-coverage-reconciliation-2026-11-08.md` observed WebKit's Networking child exit for missing network permission. Do not add network entitlement or call the direct WebKit candidate qualified.

## Narrow alternative and ownership

The worker child may use one same-thread `JSContext` to evaluate the **unchanged bundled** Viz.js runtime and its public `renderString` API. The `GraphvizRendering` package may expose its own pinned script bytes to that worker; it must not duplicate or fetch the asset. The package's existing `GraphvizFenceScanner` supplies exact UTF-16 source ranges. A successful local-only SVG is offered to the existing passive `ExportService` composition and sanitizer. A failed initialization, exception, oversized output, unaccepted SVG or deadline leaves that fence's source. A distinct accepted math item must remain independently publishable.

The context exposes no native file, network or shell bridge. It receives only a fence already admitted by the 64 KiB diagram source ceiling. The pinned runtime source itself requires a fixed location value, inert console, monotonic time, UTF-8 decoding and bounded random bytes; those pure helpers expose no URL loader or filesystem access. Viz.js initializes asynchronously; the worker pumps the same public main run loop as the prior fixed D2 JavaScriptCore probe, with no cross-thread `JSValue` transfer. The child has no promise of preempting a synchronous engine call; the unchanged parent kills/reaps it at three seconds, and the child watchdog exits at 3.5 seconds. The parent may publish only a fully marked derived reply, otherwise the already marked source fallback. No new entitlement, persistent VM, cache, server or app launch is introduced.

This is a scoped Quick Look implementation, not a change to Preview/Export renderer choice. JavaScriptCore output may have different SVG defaults than the WebKit presentation wrapper. Do not claim byte parity with Export. Retain the existing Graphviz notices and source obligations; exact final-artifact compliance remains issue #14.

## Installed-product result and limits

The first JSC candidate, [`825bef7c`](https://github.com/Joncallim/mostlytext/commit/825bef7c), built and installed but [Finder run 44421965328](https://github.com/Joncallim/mostlytext/actions/runs/44421965328) failed. The worker's pinned Viz.js initialization did not settle within its 2.25-second budget; Finder retained the authored Graphviz fence. That failure is preserved, not counted as a pass.

The helper-equipped [`03816574`](https://github.com/Joncallim/mostlytext/commit/03816574) passed [installed-provider Finder run 44422517396](https://github.com/Joncallim/mostlytext/actions/runs/44422517396) on macOS 26.7.2. The unchanged pinned asset initialized in 0.210 seconds cold and 0.088 seconds on the repeated worker request, rendered one of one fences each time, and produced a passive reply containing SVG. The actual Finder screenshot shows legible ALPHA and BETA nodes with an arrow, and its accessibility tree exposes both nodes. Ordinary GFM/math, symlink and UTF-16 source controls passed in the same test, the public app remained closed, and the installed provider/worker entitlements remained minimal. This proves one small Graphviz fixture, not the full technical Quick Look matrix, memory ceiling, final signed candidate or other diagram engines.

The follow-on branch adds a mixed malformed/valid Graphviz and math fixture, an over-64-KiB valid DOT source fallback, and a pre-Swift-bridge UTF-16 output guard. Those changes require their own exact-head Finder result before merge. The post-bridge UTF-8 output limit and passive sanitizer remain in force.

## Verification and stop conditions

- Focused package controls: fence scanning, safe SVG admission, external-resource rejection, per-item fallback, and existing Graphviz contribution behavior. Preserve the first local mistaken-positive assertion as a failed result.
- Locked local Release app build, strict changed-file lint/format, ordinary compliance and exact resource hash.
- Same-source hosted installed-provider Finder: ordinary GFM/math, linked and encoded source, one actual Graphviz SVG distinguishable from authored code, malformed/oversized graph source fallback, sandbox entitlements, no containing-app launch, bounded completion, child/helper retirement and retained screenshot/accessibility/result artifacts.
- Record cold/warm time and memory separately; a test that renders only a fixed graph, a package result or a green retry does not establish the whole issue #7 budget.

Stop this route if the actual engine cannot initialize/render under the current deadline, needs DOM/network/private authority, or produces SVG that the passive sanitizer must weaken to admit. Retain source fallback and issue #7 open. Mermaid and D2 need separate feasible implementations and remain outside this narrow slice; final signed clean-install, localisation and owner-assisted native checks also remain open.

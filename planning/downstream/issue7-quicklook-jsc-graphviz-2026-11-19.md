# Static Graphviz in the bounded Quick Look child

## Owner summary

Finder currently shows a Graphviz code fence as source. The normal export renderer uses WebKit, but the actual sandbox-only Quick Look worker could not start that renderer. Keep the existing complete source fallback and the same three-second parent deadline. Test whether the bundled Viz.js engine can produce a static SVG through public JavaScriptCore inside the short-lived child, without network or new file authority. If it cannot, leave Graphviz as authored source and do not merge this candidate.

## Baseline and observed failure

The implementation baseline is `main` `dbbcabfff0dd0ca08c62e8553ae1686199590562`. The normal worker already renders static math, with an immutable source reply marked before derived work. The selected file is read once from its descriptor; the child receives no path or directory grant. `QuickLookSource` and `ExportService` validate generated fragments and preserve source on rejection. The bundled Graphviz resource is `viz-global.js` (1,324,675 bytes, SHA-256 `c857641af952c8f82ac7243917f8563959046e5cfc44d7e84eff9a2b470f5eab`).

A direct WebKit contributor candidate compiled locally, but genuine installed-provider [run 44414497906](https://github.com/Joncallim/mostlytext/actions/runs/44414497906) failed its new Graphviz assertion. The screenshot and accessibility tree show the authored fence. In [run 44418142505](https://github.com/Joncallim/mostlytext/actions/runs/44418142505), the worker recorded two `rendererUnavailable` results in 0.211 and 0.433 seconds, with zero accepted content and normal renderer shutdown. Existing math/GFM/encoding controls preceded the failure. This does not by itself identify the OS process that refused WebKit. Earlier private provider evidence in `quicklook-evidence-coverage-reconciliation-2026-11-08.md` observed WebKit's Networking child exit for missing network permission. Do not add network entitlement or call the direct WebKit candidate qualified.

## Narrow alternative and ownership

The worker child may use one same-thread `JSContext` to evaluate the **unchanged bundled** Viz.js runtime and its public `renderString` API. The `GraphvizRendering` package may expose its own pinned script bytes to that worker; it must not duplicate or fetch the asset. The package's existing `GraphvizFenceScanner` supplies exact UTF-16 source ranges. A successful local-only SVG is offered to the existing passive `ExportService` composition and sanitizer. A failed initialization, exception, oversized output, unaccepted SVG or deadline leaves that fence's source. A distinct accepted math item must remain independently publishable.

The context exposes no native file, network, shell or URL bridge. It receives only a fence already admitted by the 64 KiB diagram source ceiling. Viz.js initializes asynchronously; the worker pumps the same public main run loop as the prior fixed D2 JavaScriptCore probe, with no cross-thread `JSValue` transfer. The child has no promise of preempting a synchronous engine call; the unchanged parent kills/reaps it at three seconds, and the child watchdog exits at 3.5 seconds. The parent may publish only a fully marked derived reply, otherwise the already marked source fallback. No new entitlement, persistent VM, cache, server or app launch is introduced.

This is a pre-implementation feasibility slice, not a change to Preview/Export renderer choice. JavaScriptCore output may have different SVG defaults than the WebKit presentation wrapper. Verify readable neutral artwork and safe generated-output admission before accepting it. Do not claim byte parity with Export. Retain the existing Graphviz notices and source obligations; exact final-artifact compliance remains issue #14.

## Verification and stop conditions

- Focused package controls: fence scanning, safe SVG admission, external-resource rejection, per-item fallback, and existing Graphviz contribution behavior. Preserve the first local mistaken-positive assertion as a failed result.
- Locked local Release app build, strict changed-file lint/format, ordinary compliance and exact resource hash.
- Same-source hosted installed-provider Finder: ordinary GFM/math, linked and encoded source, one actual Graphviz SVG distinguishable from authored code, malformed/oversized graph source fallback, sandbox entitlements, no containing-app launch, bounded completion, child/helper retirement and retained screenshot/accessibility/result artifacts.
- Record cold/warm time and memory separately; a test that renders only a fixed graph, a package result or a green retry does not establish the whole issue #7 budget.

Stop this route if the actual engine cannot initialize/render under the current deadline, needs DOM/network/private authority, or produces SVG that the passive sanitizer must weaken to admit. Retain source fallback and issue #7 open. Mermaid and D2 need separate feasible implementations and remain outside this narrow slice; final signed clean-install, localisation and owner-assisted native checks also remain open.

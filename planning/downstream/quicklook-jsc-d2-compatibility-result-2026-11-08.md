# Actual unchanged D2 engine renders in Finder through JavaScriptCore

[PR145](https://github.com/Joncallim/mostlytext/pull/145) integrates a private
fixed-input compatibility fixture at main `50f4a46de3b4a199f9def6d56e86a9f99e280e90`.
It leaves the product renderer, original qualified fixtures and canonical C
workflow unchanged. This is not production Quick Look or release acceptance.

The complete first [native run 42422289441](https://github.com/Joncallim/mostlytext/actions/runs/42422289441)
and [Compliance 42422289432](https://github.com/Joncallim/mostlytext/actions/runs/42422289432)
pass at source `fef09ea3c15d4797a51e5b4b16dd1f7bfe50ce57`. Actual tested checkout
`68b2980d4709b7de0dea175a3e8b6b5a3dc2f0bd` has the verified source/base parents
and expected merged tree. Actual native results: two cases pass, zero failures,
skips or expected failures; owned supervisor/observer complete without force.

| Actual evidence | Independently checked result |
| --- | --- |
| Runtime | Disposable hosted macOS 26.7.2, ARM, real Finder/Space invocation |
| Provider permissions | Exactly App Sandbox and user-selected-read-only; no network/JIT/private authority |
| Canonical/copied/generated inputs |32/22/25; byte-exact source and locked existing engine |
| Compiled inputs | All 75 actual roles across container/provider, automation host and UI runner; six mandatory engine/host/control/licence/notice resources |
| Actual D2 SVG |10,928 bytes; SHA256 `45d283939b9d7837024413965a00235bd15b3e87a290d84005f1d12bfda4b5a8` |
| Metadata transport |33 untruncated 384-byte parts; complete 12,622-byte record exactly matches live/direct logs and raw actual UI attachment |
| Live observer |69 immutable generations, own emitted nonce, actual provider process and direct-log correlation |
| Reference | Unchanged shipped engine/control renders through hosted Node; all 12 real typed-view copy controls pass |
| Public async control | Exact 39-byte answer-42 module: old blocking poll stays pending 0.251456 s, same-thread public loop completes in 0.007339 s |
| Observed native duration |12.166843 s for this fixed graph; no product latency/fidelity gate inferred |

Both actual screenshots were read visually. The cold case displays its original
heading and local blue PNG. The rich case displays its heading and the actual
blue-bordered ALPHA node/connector; the rest is below the screenshot viewport.
Complete native SVG bytes are separately preserved and checked. A screenshot
is not whole-graph fidelity or accessibility acceptance.

Earlier first failures remain failed and completely retained: the signed-view
copy defect, private missing-resource declaration, asynchronous initialization
stall and truncated log metadata. The last failed source had a real visible
graph but 16 of 17 truncated metadata chunks; its missing native raw SVG bytes stay
unavailable. They are never substituted with reference output. Architecture
preceded each material correction. The final small-frame transport keeps the
original 64 KiB total ceiling, exact order/count/length/SHA, original native
assertions and every deadline.

Permitted local checks: 19 preparation/transport, 5 actual temporary-resource and
13 observer controls, strict SDK typecheck only, formatting/lint/compliance and
source-preservation checks. No JavaScriptCore/Node/WASM/native product execution
ran locally. Source, provenance, raw results and actual UI were reviewed through
a scoped orthogonal self-review, which is not external independent review.

The host uses one VM and inline worker protocol. It provides neither isolation
nor preemption. The public loop permits deferred work; it cannot stop a
non-returning JavaScript/WASM call. Untrusted-work deadline/fallback, physical
worker/memory retirement, remaining engines, whole-engine fidelity/performance,
production integration, final signed RC and the full QL-REPLY contract remain
open. No original issue closure criterion is checked by this result.

The [27 exact evidence records](evidence/quicklook-jsc-d2-compatible-first-2026-11-08/manifest.json)
include the independent reader and actual main integration proof. Full original
compiled blobs/raw results/live journal remain retained alongside those records.

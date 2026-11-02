# D2 engine ownership and preparation

## Owner outcome and rationale

A pooled D2 page should reuse one initialized engine for successive diagrams.
The current glue creates a fresh worker/WebAssembly engine for every render,
leaving worker lifetime unrelated to the two-page pool. Cold engine startup also
consumes the execution deadline despite the separate bounded preparation phase.
The current Intel full run reproduced the six-request test timing out after
9.528 seconds; that is below the 15-second admission ceiling and consistent with
an execution timeout. Phase attribution is source-supported, not yet a native
profiling proof. Do not change either ceiling to obtain green tests.

## Baseline and contract

Live master is 87d8d48b, transferred through #578. Combined source is 9c463f3f.
The bundled D2 0.1.33 wrapper constructor calls init, creates one Worker and
exposes ready; sendMessage has a single currentResolve/currentReject pair.
render.js currently constructs a new D2 on every request. No vendor byte or
lockfile update is needed. First-party render.js is already inventory-covered.

Keep DiagramWebKitPool ownership and module direction. Add an optional async
preparePage callback to its existing resource-backed initializer. The factory
loads the contained page, awaits preparation, and tears it down on preparation
failure/cancellation. Existing pool admission/physical cleanup remains the owner;
the page is not handed to a borrower until preparation completes. Other
renderers use the unchanged default no-op preparation. This narrowly amends the
existing factory interface; no new module, global worker pool or network access
is introduced.

D2's first-party glue creates exactly one engine per page and publishes an
explicit ready function. Preparation awaits that function before acquisition;
each render uses the same instance. The existing pool serializes use of each
page, which is required by the wrapper's single outstanding reply slot. Page
retirement/shutdown bounds the engine's lifetime. Invalid-source failure must
not allocate a new engine or contaminate a later valid request.

The admission default remains 15 seconds (queue, page loading and cold engine
preparation); JavaScript rendering remains five seconds after readiness. The
one-millisecond timeout negative and all existing output/containment tests stay.
Do not warm by rendering user data or make a network request. Make preparation
failure explicit and retire the page, without caching a failed engine globally.

## Verification and stop conditions

Use the exact bundled wrapper with a fixture Worker transport in Node to count
constructor/worker allocations and test ready/failure/reuse. This is a JavaScript
transport fixture, not actual WebAssembly or WebKit acceptance; record adapters.
The old render glue must fail the worker-bound control. Add genuine WebKit pool
preparation ordering/failure/cancellation controls to the hosted complete suite.
Retain existing real D2 repeated/concurrent/timeout/syntax/appearance tests.
Run strict lint/format, Compliance/inventory, compile-only local app/tests and
complete hosted package/app/build checks. No local product/WebKit tests run on
the owner account. Final native/renderer calibration and #113/#155 remain open.

## Initial source controls

The exact bundled wrapper plus fixture Worker transport reproduces three worker
allocations for one failed and two successful requests on the old glue. The
repaired glue uses one worker, exposes readiness and returns an explicit failed
readiness result. DOM canvas postprocessing is a named fixture adapter; no
actual WebAssembly/WebKit acceptance is inferred. Initial fixture setup missed
Node's atob global; that setup failure is retained separately from the real
3-versus-1 worker negative. The three new genuine WebKit preparation controls
compile locally without executing. The pre-existing unnecessary-await warning
in the default retirement callback is resolved by declaring its MainActor
isolation explicitly; teardown behavior remains actor-correct.

Full combined Intel run 41531272465 executed all 3,314 package tests / 461 suites
and failed with one unexpected D2 concurrent-render timeout plus the two existing
known issues. All seventeen previous bookmark assertions, editing budgets,
CommandBridge admission, file-probe and JSON-outline failures do not recur in
that run. App/build steps were skipped after the package failure; post-pass
helper hash checks were not reached. This is a retained failure, not a pass.

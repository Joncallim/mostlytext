# Test the existing D2 engine in the network-denied JavaScriptCore provider

## Owner outcome and live baseline

Main97d8cf605400a0137c021a46aa195ff903c52696 integrates PR143's actual minimal
JavaScriptCore/WebAssembly positive. That finite39-byte module is not D2. The
actual frozen PR140 WebKit engine attempt still fails after Networking exits
for missing network permission. Do not change its source, retry it unchanged,
add permissions or infer a production pass.

This named pre-implementation spike asks one question: can the byte-identical
existing bundled D2 browser/Go/WASM engine compile and render one fixed tiny
D2 graph inside public JavaScriptCore under exactly the same two provider
permissions? A positive SVG would justify a later execution-host decision; a
precise first failure will identify the next boundary. No shipping renderer,
engine replacement, third renderer, package API or product behaviour changes.

## Ready state, boundaries and fixed inputs

The upstream minimal VM primitive, full three-bundle capture, actual cold Finder
control, live nonce/direct provider observation and owned executor are merged.
Read current engine and original failure before this decision. Keep those
sources unchanged. Add only a separate private fixture/scripts/workflow and
this architecture. Copy the actual D2 browser asset unchanged from the current
product into that private bundle and bind its SHA in canonical/copied/generated/
compiled records. No new external dependency or third-party vendored asset.

The input is a compiled-in fixed ASCII graph with two labelled nodes and one
edge, not selected-file text or authored executable script. The selected file
remains the28-byte generated harmless Markdown control. No arbitrary resource
URL, file reader, network bridge, ObjC bridge, AppGroup, JIT/private entitlement,
containing-app launch or local product/engine runtime is allowed.

## Exact execution-host adaptation

The bundled browser API creates one Blob/Worker, decodes embedded Go/WASM/ELK
assets and speaks init/ready/compile/render messages. JavaScriptCore has no
Worker/DOM/fetch. A private adapter supplies only UTF-8 encode/decode, base64,
real OS random bytes, monotonic time and a bounded in-memory timer queue. Swift
exports only those value-level constant-control operations, never native objects
or filesystem/network access. The adapter implements one inline Worker protocol
inside the same VM; it is explicitly NOT a separate worker/isolation boundary.

Keep browser/Go/WASM engine bytes unchanged. The adapter accepts the one actual
Blob containing Go glue and worker module. Require exactly the two known module
export declarations before removing only those export keywords for classic
Function evaluation; retain the original module texts and transformed digest.
Unknown structure fails. Preserve all engine computation and actual ready/
compile/render responses. No mock SVG, hand-written D2 parser, simulated delay,
request-result substitution or neutralisation of engine failures.

The VM and all JSValues stay on the one calling executor/thread with no await
or Sendable transfer. Swift drives queued timer callbacks on that same thread
while waiting for fixed graph completion, up to15seconds between VM calls.
A VM call can itself block: this is NOT an arbitrary-work timeout, cancellation,
physical retirement or bounded-memory proof. The owned native120second case
and15minute workflow limits remain unchanged; no deadline claims or padding.
No concurrent engine or production admission policy is added here.

## Journey, failure model and evidence

Retain the byte-identical original cold static Finder positive. A second actual
Finder case selects the generated D2 control, presses Space and requires a
visible rich-SVG marker, real SVG data in a raw attachment, compiled labels and
correlated provider metadata/factory identity. SVG must begin with svg/XML,
contain the actual node labels and vector geometry, have no script/foreignObject/
remote reference, and stay below256KiB. Freeze reply bytes before the factory.
An engine exception, unsupported host API, wrong/missing ready/result, malformed/
unsafe SVG, exhausted host budget or missing positive fails this spike; retain
its precise bounded phase/error and original complete first outcome.

Before native execution, independently run the same private adapter + exact
browser asset + fixed graph on the guarded hosted runner's reference Node VM.
Use explicit value bridges and a fresh VM context, not Node's Worker substitute
or a different renderer. Require real SVG and adapter UTF-8/base64/random/timer
controls there. Capture exact bridge/adapter/engine hashes, command, Node binary/
version/result. This checks host logic separately; it is not native acceptance.

Preserve all canonical/copied/generated inputs and all actual three signed
bundle/resources before native execution, exact sandbox+selected-read-only
permissions before/after/runtime, live/direct own logs and nonce, raw xcresult,
AX/screenshot/result attachment and normal owned lifecycle. Download complete
first native and Compliance outcomes before any correction. Independently verify
actual parents/tree/source/assets/blobs/permissions/results and inspect screenshots.
No unchanged failed native retry, skipped/expected pass or widened permission.

## Slices and stop conditions

1. Commit this architecture before code. Implement the small private host and
   pure corruption/source/authority controls. Strict optimized SDK typecheck,
   changed Swift formatting/lint, Python/YAML, compliance and diff checks only
   locally; never execute JSC/Node/WASM or build/launch an app on CORTANA.
2. Run guarded hosted reference plus actual two-case Finder spike once. Preserve
   complete first outcomes. Classify failure precisely before a new written
   correction. A new renderer/authority/product seam requires a separate decision.
3. If genuinely positive, scope review/integration to compatibility diagnostic
   and record its limits. No original issue criterion closes solely from this
   fixed-input host test. Real deadlines/fallback/retirement, untrusted corpus,
   semantics/fidelity/theme, resource budgets and production shared presentation
   remain subsequent gates under #7/#8/#17.

The first implementation uses a narrower48KiB actual SVG/64KiB encoded record
budget within the architecture's256KiB ceiling. Numbered768-byte record chunks
plus an exact length/SHA-256 terminal avoid relying on one large OSLog string;
UI and source controls require complete ordered reconstruction of the original
bytes and bind actual engine/adapter/module-transform identities. A fixed two-
node graph uses the existing compile/render API; no product DOM/theme/canvas
postprocessing is inferred as verified by raw-engine compatibility.

Local14pure schema/chunk/identity/authority controls,13observer and3owned controls
pass. Strict optimized SDK typechecks of exact provider/bridge and actual UI,
changed Swift format/strict lint, Python/YAML, source compliance and unchanged
product/original cold/probe controls pass. Local checks do not execute any
JavaScriptCore/Node/WASM runtime or build/launch an app or extension. The actual
first guarded reference/native run remains pending and must be retained whole.

The generated private resource bundle also preserves the current D2 licence,
unchanged D2 modification notice and complete generated third-party notice text,
with canonical/copied/generated/compiled byte identity. The adapter's explicit
in-memory module-export conversion is separately recorded; it never overwrites
the original browser asset or its notice. This is not closure of independent
source/font/rights review or the exact released-artifact compliance gate.

## First reference failure and bounded phase diagnosis

Source dff0b156101755d1105d75a69047c71699ad65e7 /actual92beb896 first
native42414107222 FAILS during hosted Node reference execution. Compliance
42414107131 passes. Both complete first outcomes/logZIP/artifacts are retained
and independently verified:28canonical/19copied inputs and unchanged actual
D2 asset/licence/notice/full notices. Reference Nodev24.22.2 exits1 with
ERR_SCRIPT_EXECUTION_TIMEOUT after15000ms at reference.cjs22 (one of the three
asset evaluations). The exact asset/subphase is not recorded. Xcode generation,
build, compiled admission, real Finder and actual D2 SVG are NOT_RUN. Do not
classify this as a native JavaScriptCore refusal or increase the time budget.
The later always-verifier KeyError reference_module is secondary to that timeout.

A bounded diagnostic correction records fixed phase markers before/after each
asset evaluation and the actual worker/ready/compile/render transitions. Node
writes a small separate phase journal even when VM evaluation throws. Native
uses the same value-only fixed phase bridge and own log. It adds no engine
substitution, permissions, workaround, deadline padding or accepted failure.
Persist the original reference outcome before post-failure verification, which
must explicitly refuse an unadmitted stage rather than implying native work ran.
The next first outcome must again be preserved complete before any correction.

Phase-only source d3ec8f40's complete first native42414457718 fails earlier in
its own reference phase-name validator: the allowed[a-z-] grammar excludes
fixed asset-d2-browser-start. Its journal shows host start/end and no D2 asset
start. Compliance42414457637 passes; complete firsts and28/19source inputs are
retained and independently verified. This is an avoidable diagnostic bug, not
reproduction/explanation of the original15second engine timeout. Correct the
phase grammar to include digits and check every actual fixed/dynamic phase name
against the actual reference script's boundary before publication. Retain the
same engine, reference/native deadlines, authority and real-SVG requirements.

Corrected phase-name source d24ad839 first native42414723487 still fails;
Compliance42414723560 passes. Both complete firsts and28/19inputs are retained
and independently verified. Exact13row phase history proves host and browser
asset evaluation finish, worker Go/module setup finishes (~0.75s process uptime)
and engine-await-ready begins. No message-init or asset-control-end is observed.
The outer reference process reaches its unchanged45second timeout. Its original
reference-module.json records TimeoutExpired; reference-module.log is absent
because subprocess.run raised before the old output-write line. Native project/
build/Finder remain NOT_RUN. This is not an observed native JavaScriptCore limit.

Next bounded diagnosis wraps the actual frozen browser's existing global Bf
WASM-unpack function only with before/after fixed markers and calls the original
function unchanged. This distinguishes synchronous unpack from later readiness
without replacing/decompressing/substituting any payload or increasing a limit.
The exact browser asset bytes and original computation remain unchanged. Preserve
actual TimeoutExpired partial stdout/stderr in finally-path output capture even
when the child is killed; no synthetic result or missing-byte claim. No native
attempt is admitted unless the original genuine reference SVG positive passes.

## Verified signed-array repair for the next Mac candidate

The separate guarded Linux diagnosis preserves exact engine bytes and no Mac
acceptance is inferred. Its source020c85f4 shows unpack finishes in0.447seconds;
e8c45c57 observes the actual result Int8Array and12verbatim actual clone controls:
1passes/11fail, including signed bytes converted into an ordinary Object. Narrow
repair ff921993 preserves visible bytes and view kind for all ArrayBuffer views.
Actual first Linux42416702780 passes all12controls and the unchanged real D2
engine/control/reference, reporting10,928SVG bytes and a complete28phase history
ending render at2.253seconds process uptime (whole reference4.753seconds). Source,
copy, Node and before/after function identity are independently verified. Its
first reference retained SVG length/hash, not raw SVG bytes; no visual/fidelity
or native claim follows. Complete first success and earlier failures are retained.

The obsolete d7c45fb4 Mac diagnostic42415176368 was freshly verified queued with
zero steps, then cancelled before executor/build/Finder. Its completed cancelled
metadata, empty actual log archive and empty artifact list are retained and
independently verified. It is NOT_RUN, never a native failure or pass. Companion
Compliance passes. All PR146 first gates remain unchanged and running.

Before code, adopt only the proved BufferSource copy repair and its real12case
control in the existing private Mac host. Keep the engine, fixed graph, two
permissions, original cold/rich Finder assertions and all deadlines. Persist
actual reference SVG bytes and verify their own length/hash; do not assume
byte-equality or theme fidelity across Node/JavaScriptCore. Preserve complete
first corrected Mac outcome before further correction. No production host,
worker isolation, untrusted-work deadline, memory or full QL-REPLY claim.

## Actual first Mac packaging refusal and mandatory asset preflight

Source42d7a806 first native42417108375 FAILS; Compliance42417108349 passes.
Complete firsts and actual29canonical/20copied/23generated/69compiled roles are
retained and independently verified at checkout1cb1923b. Real reference Node
passes all12copy controls and retains its actual10,928byte SVG with exact hash.
Raw Finder results: unchanged cold static case passes; rich case fails, no skips/
expected failures, normal owned65/no timeout/cancel/force. There is no D2 phase.

The actual generated project has no PBXResourcesBuildPhase or JS references,
and its complete actual inventory correctly records all six mandatory engine/
host/control/notice resources absent from the provider. The wrong target-level
resources declaration was ignored. This is a private packaging/preflight defect;
D2 script evaluation is NOT_REACHED, not JavaScriptCore/WASM or event-loop refusal.
No historical missing resource byte is backfilled or called captured.

Correct only the provider's XcodeGen sources entry to explicitly assign the
Resources group to buildPhase:resources, as specified by the primary XcodeGen
project specification. Before native admission, require the actual provider's
six regular non-symlink resource files byte-equal the exact generated inputs.
Store their digests in the actual built identity and complete compiled inventory,
and recheck after UI. Test missing/changed/symlinked resources and changed-after-
seal data with actual temporary files against the frozen old capture function,
then require corrected positives. Keep engine bytes, two permissions, native
assertions and every deadline unchanged; preserve the next actual first outcome
before any further correction. No production host or generic packaging policy
is added. See https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#sources.

## Observe asynchronous VM work and pump only its public owner-thread run loop

Source4ce49ee6 first native42420404964 fails; Compliance42420404921 passes.
Complete firsts and30/20/23/75source/copy/generated/actual compiled roles verify.
All six mandatory resources are now present, byte-identical and bound. Actual
unchanged cold Finder passes, rich fails, no skips/expected/force. Actual13phase
markers reach WASM unpack/Int8Array and message-init-return. No engine-ready,
compile, render, result or rich reply factory is observed. Screenshots and raw
results retain that failure; no native D2 or scheduling fix is inferred.

Primary WebKit source describes asynchronous WebAssembly validation/instantiation
as deferred work on the VM run loop. The current private synchronous callback
only evaluates __hostTick and Thread.sleep; public owner-thread run-loop pumping
is a concrete hypothesis, not yet the demonstrated sole cause. References:
https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/wasm/js/JSWebAssembly.cpp
https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/runtime/DeferredWorkTimer.cpp

Before the unchanged real engine, use a separate public JSContext on this same
callback thread and the already qualified exact39byte answer42 module. Invoke
actual asynchronous WebAssembly.instantiate, observe bounded0.25second old-style
blocking polling, then permit only the same thread public default RunLoop within
a fixed2second total control deadline. Record whether old polling completed or
remained pending; do not require an invented universal failure or infer callback
progress. Require actual answer42 with no exception, preserve thread identity,
and publish a bounded independent control record before the D2 attempt even if
the later rich assertion fails. No private JSC API, native objects, alternate
engine, network/JIT authority or cross-thread VM transfer. This control is a
scheduler diagnostic, never worker isolation or preemptive execution protection.

Only replace the actual D2 wait-loop sleep with public same-thread default-mode
RunLoop pumping, checking its existing monotonic15second deadline between calls.
Keep the engine/control/host JS bytes, real graph, exact two provider permissions,
original cold/rich Finder assertions and all outer/UI limits unchanged. The
existing15seconds still includes setup; no longer budget is granted. Emit a
bounded explicit host-wait diagnostic before refusal. A public loop cannot
preempt a non-returning JS/WASM call and is not a production cancellation or
resource policy. Preserve the next complete first before any further correction.

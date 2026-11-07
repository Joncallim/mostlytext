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

# Test a physically bounded worker inside the Quick Look sandbox

## Owner outcome and current baseline

Main324155cc9cfb45116d32a2a05c2f0d392507ecea contains the actual public
JavaScriptCore/WebAssembly primitive and unchanged-D2 compatibility evidence.
The latter is one fixed graph,12.17seconds, in the provider's own VM/thread.
It cannot preempt hostile execution or prove physical deadline/memory retirement.
The earlier native Finder close control also proved provider task cancellation
is not automatically propagated. Those limits remain; no production Quick Look
target or untrusted rendering is activated here.

This named pre-implementation spike asks one narrower question: can the real
Finder-hosted sandboxed provider spawn an embedded, signed, sandbox-inheriting
command-line helper, observe normal completion, and observe a deliberately held
helper terminate itself by an independent hard deadline? A process boundary could
support physical retirement later. A successful harmless control is not admission
of untrusted diagrams, calibrated resource budgets or complete QL-REPLY acceptance.

Apple documents exactly two sandbox entitlements for child tools: app-sandbox
and inherit. Its example parent has sandbox and user-selected-read-only. This
supports testing, not assuming, extension execution. Sources:
https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app
https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
XcodeGen dependency.copy(destination: executables), embed:true/link:false is
specified in https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md.
A local SDK -typecheck -application-extension admits public Process.run/wait only;
no helper, app, engine or extension was executed/built locally.

## Fixed ownership, capabilities and interfaces

Extend only the existing private quicklook-jsc-probe fixture/controller/tests.
Keep its original two cold-static and39byte-JavaScriptCore cases byte-unchanged,
actual reference control, live own-nonce host observer, owned executor, all bundle
capture and original limits. Add one third real Finder case and a fixed generated
worker filename. Product MacDown2 tree, dependencies/pins, public CLI, all original
UI38 inputs and canonical original qualification workflows stay unchanged.

Provider retains exactly sandbox+user-selected-read-only; no network/JIT/private
API/exception/app-group/debug/process capability is added. The child declares
exactly sandbox+inherit, verified in actual downloaded signature metadata and
inside the real helper before work. It receives no document path, bookmark,
parent-folder grant, script, engine, arbitrary executable or environment override.
Its executable is resolved as the exact regular non-symlink sibling of the
provider executable in its own signed bundle, never PATH or a dynamic command.

The helper accepts only normal/held mode, a positive request ID and exact actual
parent PID. Verify real runner UID501/name/home-prefix/OS26 and parent identity,
then emit bounded JSON with actual child/parent IDs, request/mode and real own
entitlement flags. Normal mode exits0. Held mode installs a separate dispatch
timer for500ms, then deliberately waits; the timer sends SIGKILL to getpid(), never
an incoming or external PID. It has no grandchildren. No owner account is used.

The provider uses public Process, exact arguments and pipes. Snapshot its actual
positive child PID; wait for this fixed harmless bounded child; read at most the
bounded expected fixed output; compare actual child/parent/request/mode. Record
actual termination reason/status, elapsed time and kill(pid,0)==ESRCH after reaping
for both children. Require distinct actual PIDs, normal exit0 versus held signal9,
positive exact entitlements and completion within3seconds each. No supervisor
kill is relabelled as normal retirement. Emit each bounded child record once
(max384JSONbytes) to the already-admitted live log and a frozen HTML reply. The
provider's callback thread is recorded; blocking it here is not a production
executor design or UI performance claim. Failure remains an actual failed spike.

## Evidence flow, lifecycle and resource scope

Generate the new fixed Markdown fixture next to existing controls. The third
XCUITest opens it through Finder, requires both actual normal/physical-deadline
markers, reads exact own-generation provider records, keeps full JSON/accessibility
and screenshot attachments, closes Quick Look and requires containing app absent.
Original two native cases must still execute. Exact source/generated inputs,
all actual regular files in all three signed bundles (including the new child),
child/provider entitlements and actual raw3case result/owned lifecycle are bound
before/after. Add the child to explicit compiled roles and preserve all existing
roles, capture budgets, live snapshots and original assertions.

Provider/child scripts are finite compiled controls; no authored input enters
Process, a VM or shell. Existing file/sibling proof remains separately scoped;
static sandbox declarations are not claimed as new empirical no-network proof.
The held timer is intentionally independent of Finder task cancellation. It
qualifies only actual self-retirement of this harmless child, not arbitrary C/JS
preemption, process-spawn latency under load, child memory budgets or cancellation
of a production renderer. Every complete first workflow/log/artifact/raw result
is retained before any source correction. No unchanged retry, limit increase,
skipped original case or fallback permission broadening.

## Slices and stop conditions

1. Commit this decision before implementation. Local source/SDK typecheck only;
   no local Xcode product/extension/helper build, JavaScriptCore/WASM/runtime.
2. Add signed helper, fixed provider routing, third actual Finder case and exact
   checker/negative pure controls. Validate source preservation, full style/strict
   lint, YAML and compliance; use the existing live-observer tests unchanged.
3. Freeze/publish once. Guarded GHA builds and executes all3 native cases; retain
   complete original first Compliance/native/logZIPs/artifacts. Independently
   verify actual source/pins/compiled bytes/signatures/JSON/raw results/normal owned
   lifecycle and read screenshots. A spawn/sandbox/signing/SDK failure stays failed;
   stop rather than add authority or a private API. Revise a false assumption
   explicitly before any new architecture or correction.
4. Scoped orthogonal self-review, issue7/8/17 reconciliation and expected-head
   integration only if the scoped spike is genuinely ready. No original broad
   Quick Look criterion, production registration, full engine isolation/budgets,
   final signed-artifact, separate-account or owner acceptance is inferred.

## Revised decision: identify the actual refused launch before remedy

Current main38f14a37 additionally contains independent PDF and process-receipt
changes; the private worker inputs remain frozen atabb86656. Complete original
native42430116954FAIL and Compliance42430116919PASS are retained in15exact
records before this code revision. Independent verification binds26canonical/
16copied/19generated inputs,71actual downloaded compiled roles and actual child
signature sandbox+inherit. Both original cases pass; the third fails before
child/factory records with numeric Process.run error4. Its domain, description
and underlying error were not captured. This cannot establish sandbox denial
or any cause; normal/held retirement controls were not reached.

Revise only private diagnostic output/admission, with no launch-policy change.
On actual Process.run failure collect bounded NSError domain/code/description
and at most two underlying errors; actual worker path, Unix permissions,
readable/executable access results/errno, and current/default Process directory.
Use actual observations; do not infer denied rights from declarations. Bound
all strings and the whole JSON to4096bytes. Emit384raw-byte base64 chunks with
request/index/count/full-SHA256 (each native log message below700bytes), using
the already-owned live provider log. Keep the original throw/UI failure.

Factor unchanged host-stream/nonce/compiled-control/snapshot/lifecycle validation
from UI-success validation. A separate worker-spawn-errors.json is written from
validated own-nonce raw generations BEFORE the original success checker rejects
UI65. That diagnostic explicitly records the real failed UI status and never
qualifies child work or changes the original three cases/assertions. Require
complete unique bounded chunks/digest, matching request/actual provider identity
and executable hash; fail closed on truncation, duplicate, other-request or
malformed evidence. Empty errors are explicit if no launch failure occurs.

No child/provider entitlement, authority, launch path, environment, timing,
original tests, observer/executor, production or dependency change. Native only
on guarded GHA; local source/typecheck and pure hostile frame controls. Preserve
all complete firsts and inspect actual error before selecting a remedy. No
unchanged retry, test waiver, private API or broadened privilege. This diagnosis
can pass extraction while the whole original native spike remains FAILED.

## Actual precise first outcome and recorder correction

Complete native42432445955FAIL / Compliance42432446029PASS at00cc5af3 are
retained before correction. Independent reader verifies all26canonical/19generated/
71downloaded compiled inputs, original2PASS/worker1FAIL, actual child signature,
all raw live-stream nonce/snapshot generations and exact three complete chunks.
Decoded NSError is NSCocoaErrorDomain4, file does not exist, no underlying error.
Actual worker0755/read_access0/read_errno0 but execute_access-1/errno1 (EPERM);
current/default Process directory is the actual provider container Data. The
actual worker bytes match the built signature/hash. Execution access is refused
for this exact embedded file. No child/held deadline admitted; precise OS policy
source or impossibility of every supported process/XPC design is not proven.

The independent decoder recovers all actual error facts without rerunning native
work. However, worker-spawn-errors.json was not written: the driver records its
expected RuntimeError('First actual Finder UI execution failed: 65') in errors,
and the refactored recorder still rejects every driver error. Correct that
recorder boundary only: admit this exact driver exception solely when UI status
is65 and actual owned status65, no timeout/cancellation/app cleanup, and exact
owned checkout. Reject unknown driver errors, any observer error, other statuses
or missing owned evidence. Full UI success still requires status0 and errors[],
so the whole spike stays failed. Model this actual exception in the pure control,
with unknown-error/owned-timeout and changed-checkout negatives. No permissions,
launch operation, worker/test assertions, limits or observer/executor changes.
The direct Process route is not admitted for production; selecting a different
public process architecture needs its own written decision and real Finder proof.

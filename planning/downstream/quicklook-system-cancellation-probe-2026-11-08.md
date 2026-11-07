# Observe what Finder closure does to a pending Quick Look provider request

## Owner summary and baseline

Find out whether closing a genuinely pending Finder preview cancels the Swift
async provider task, or whether that task keeps running until its own completion.
Actual main isd7cff043750123aea66e50406884ca73917885af. The static cold-Finder
route is qualified through PR118. PR137's separate actual native reply-retention
probe is qualified but unmerged; it cannot substitute for system cancellation.
No production Quick Look target exists and shared rendering remains held.

This is a bounded platform observation. A request that completes after Finder
closure is a meaningful negative cancellation-propagation observation, not a
production cancellation pass. The subsequent execution-placement/deadline design
must consume the actual result before broad integration. No invented callback,
manual Task.cancel, mock Finder or owner-account execution is allowed.

## SDK contract and ownership

Actual macOS26 QLFilePreviewRequest exposes only fileURL; QLPreviewingController
exposes providePreview(for:completionHandler:). Neither inspected header declares
a cancellation callback. The Swift async importer does not establish propagation.
Copy the qualified private fixture into a separate cancellation-only fixture and
leave its original directory, controller, permissions and workflow byte-identical.
The new provider still declares only sandbox + user-selected read-only access,
no default document handler, network, App Group, root-read or debugger exceptions.
Use the same reserved identity only on its own disposable hosted Mac.

A generated selected cancellation Markdown file contains only the same authored
28-byte static source. Its separate provider branch records monotonic timestamps
and request ID before an explicitly cooperative ten-second Task.sleep. A real
withTaskCancellationHandler records actual task cancellation if the framework
propagates it; a cancellation error is returned normally as that one async
request's error. If no cancellation arrives, record actual completion after the
wait and return the existing immutable static reply. This wait is an instrumented
pending-request window, not a slow real-renderer or two-second fallback proof.
No production renderer or source is modified or executed.

## Actual UI sequence and failure model

Retain the complete original cold-Finder test as a positive. In a separate new
UI test, actually select the generated cancellation file, invoke Space, require
the real named Quick Look window and an actual provider-start log while its wait
is still pending, then send Escape. Require that exact window to disappear and
capture real UI/monotonic close evidence BEFORE provider wait completion. Retain
screenshots/accessibility state and assert the containing fixture never launches.

A cancellation may arrive between Escape and observed window disappearance; do
not incorrectly require cancellation to wait for window disappearance. A normal
wait-completion must follow actual UI close, or this was not the intended pending
closure observation.

The UI test may read only this probe's own public provider log messages, through
bounded system-log queries. It must not signal, cancel or call the provider task.
After closure observe its actual terminal cancellation-or-wait-completion event.
The producer validator correlates unique request ID and strict monotonic ordering
start < observed pending < Escape; Escape precedes both actual UI close and terminal. It records which actual
outcome occurred; both data points are legitimate answers to the feasibility
question. Missing callbacks/UI/ordering, premature completed work, mixed requests,
wrong source/permissions/executables, timeout or forced cleanup fail the probe.
Never relabel a failed first attempt or raise an existing cold-Finder deadline.

The separate new UI test has a bounded one-minute overall allowance, five-second
window/start/close observations and at most15seconds to observe the intentionally
ten-second terminal event. Original cold-Finder5/10/15second checks stay intact.
No retries or repetition switches. One first source runs once, and its complete
original/raw outcomes are retained before a demonstrated fixture correction.

## Execution, evidence and integration

Architecture precedes code. New files live in .github/quicklook-cancellation-probe,
a distinct guarded preparation script, pure result/admission controls and its own
same-repository/manual workflow. Preparation requires real hosted runner account/
UID/home/temp/checkout/macOS26ARM, rejects optimized Python before writes, builds/
ad-hoc seals only its private fixture on the hosted Mac and checks exact full
provider entitlements before/after. Local work is source and Swift SDK type checks
only; no executable, Xcode project build, implicit registration or GUI runs locally.

Bind all actual source/generated inputs, app/provider/test/runner/xctestrun bytes,
UI execution identity and owned result. Preserve binaries/metadata needed for
independent download verification, complete first logs and actual xcresult. Actual
UI methods and first static positive must run, not merely compile. Download and
independently read raw cases, phase logs, observed timestamps, provider logs,
entitlements and binaries. Wait for PR136's frozen fullCI before advancing main;
intake actual subsequent main and requalify a combined head before merge.

This remains a private feasibility probe. Retained reply ownership/direct factory
calls, actual failure-once delivery, real-renderer fallback, production shared
presentation/extension, final signed registration/performance/VoiceOver and the
original issue7 requirements remain separate. Record a negative cancellation
observation plainly; do not call it safe cancellation or permission to ignore
live worker occupancy/retained bytes.

## First actual window-query failure and correction contract

First81a140c6/run42397600403 genuinely passes the original cold positive and
fails only the new filename-as-window-title precondition. All16canonical/
13generated inputs, minimal permissions and11downloaded execution roles are
independently verified; actual2cases/1pass/1fail/0skip/0expected, ownednormal65.
Failure AX has one actual Keyboard Focused window titled Quick Look and a
pending spinner. The real provider wait starts and completes10.658797s later;
Escape is NOT_RUN, so no system cancellation outcome follows. Both first
workflows/logs/artifacts are complete/retained before this material correction.
XCTest abort skips the Swift defer's custom attachment; automatic AX/video stay.

Bind the same5second window query to the actual observed Quick Look title,
require exactly one matching window and its actual spinner, and explicitly
capture this state before a failed window assertion. Keep all provider behavior,
source/permissions, original cold test,10second wait, Escape/disappearance,
post-Escape correlation and original deadlines unchanged. This corrects observed
fixture window identity, not framework/product behavior or a cancellation waiver.

## First UI log-reader context refusal and host-observer correction

First corrected787497b1/run42398317823 passes original cold Finder and all new
actual window/unique/spinner preconditions, then the UI child log command exits64.
Its stderr was discarded; do not invent a specific permission/service cause.
Host-workflow log show succeeds and captures the actual pending/terminal events.
All16source/13generated/11downloaded execution roles and actual2/1/1/0skip/0expected
results are verified; Escape and system cancellation observation are NOT_RUN.
Both complete first outcomes are retained before any correction.

Read-only signature inspection confirms the existing SDK-injected UI runner can
read /; this is distinct from the exact two provider permissions. Move only
observation to a guarded, bounded host recorder. It queries the same own public
provider log subsystem, requires command exit0, preserves stderr on failure and
atomically publishes bounded JSON under this generated temporary probe root.
The UI reads that record through its existing read-only capability; no App Group,
network service, entitlement/TCC change, provider signal or fake readiness event.
Keep equivalent schema/success/correlation checks, original cold method/provider/
10second wait/window/spinner/5second waits/Escape/disappearance/terminal limits.

A guarded private driver starts the owned recorder before actual UI execution,
waits at most5seconds for its genuine initial log-query snapshot, runs the same
owned xcodebuild command, then stops/reaps only that recorder after UI completion.
Recorder log calls are individually bounded; total lifetime300seconds, at most128
changed snapshots each128KiB, and exact source/checkouts/commands/statuses/journal
hashes are retained. A failed query, missing startup, recorder timeout, forced
cleanup or nonzero UI outcome fails. A recorder normal stop is observer cleanup,
never described as system task cancellation. Native provider callbacks remain
unchanged and final direct host logs independently validate actual UI timestamps
against the provider request before either feasibility outcome is accepted.

Add pure file/sequence/cap and lifecycle/classification controls plus real normal/
optimized foreign-host refusals. Capture all new observer/driver sources in the
execution inventory. SDK type check only locally, no framework runtime. Preserve
new first failure rather than retry unchanged or change native waits. This is an
execution-context correction for diagnostic observation, not production access,
cancellation safety, slow-renderer fallback or whole platform acceptance.

Host-observer source preparation passes15existing correlation controls,9new
atomic-file/sequence/cap/identity/normal-stop controls and3owned lifecycle controls.
Normal/optimized observer/driver foreign-host execution refuses before preparation.
Strict SDK type checks, pinned formatting/strict lint, Python/YAML and source
compliance pass. No native outcome on this changed observer is inferred. An
intentional recorder stop after UI completion may interrupt its last log query;
that status is retained separately and never called provider-task cancellation.
All real log queries supplying published snapshots must finish0. Exact direct
post-run provider logs remain the independent correlation source.

## Historical-scan startup refusal and live-stream execution boundary

First0e1b3200/run42400199251 compiles/seals all roles but the initial historical
host log scan exceeds its3second limit before UI starts. Both first outcomes and
all19canonical/13generated/11downloaded execution roles are retained/verified at
actualff185303. UI/Escape/cancellation are NOT_RUN. Do not increase that timeout
or claim a cancelled/failed UI journey. Intake actual mainc1edd7a1, containing
qualified PR136/137, before the next materially changed first publication.

Use a single persistent own-subsystem log stream in newline-delimited JSON
(`log help stream` confirms ndjson support). Its lifetime stays300seconds and
startup stays5seconds. This replaces the historical-scan execution model rather
than giving the old scan more time. Stream process must remain live until the
existing owned driver stops it after UI; unexpected exit, malformed/lost records,
forced cleanup or uncorrelated data fail. An expected post-UI stream stop is
observer cleanup, not provider task cancellation.

Before UI, prove the real stream channel using a tiny private SDK console that
emits one fresh UUID control nonce through OSLog in a distinct observer subsystem.
Compile it with strict optimized Swift on the hosted Mac only; capture exact
source/command/binary before/after alongside the other roles. It requires actual
runner UID/name/home/macOS26/repository and its exact generated executable path.
The recorder can emit successful benign control pulses at most25times under the
same5second startup bound until the actual matching nonce appears in the live
stream. This is channel admission, never a native-suite retry or fake provider
callback. Each control invocation has the unchanged3second command bound and
nonzero/timeout fails. UI starts only after that real echo; its data file contains
only actual provider messages, with the same immutable128generation/128KiB caps.

Persist raw stream bytes/records, actual control attempts/echo, source/binary
identity and observed record positions for every published snapshot. Independently
re-read direct post-run provider AND control logs, compiled blobs, owned driver/
stream lifecycle and actual UI attachment. No permissions/TCC/AppGroup/network
service changes. Original cold positive/provider/read path/10second wait/window/
spinner/Escape/closure/terminal checks remain byte-identical. Strict source/pure
parser/correlation tests precede one new first native run; retain any new refusal.

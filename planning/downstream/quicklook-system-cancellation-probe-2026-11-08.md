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

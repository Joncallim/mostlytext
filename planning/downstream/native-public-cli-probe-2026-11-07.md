# Verify the public CLI against a normally launched app

## Owner summary

Test the actual embedded command and user-created `mostlytext` symlink against
an ordinary Release app on a fresh hosted macOS26 runner. This can establish a
bounded warm file/stdin/wait route without launching the app in the protected
owner account or using signing keys. It cannot establish trusted cold launch,
installed migration, Finder, owner acceptance or an exact signed candidate.

## Baseline and question

Current main c3e9fd066277b29e653a01045d6ad24e5e1fb1e6 includes the app-bound
packaging correction PR110. Read AGENTS, EPIC_STANDARD, RELEASE_HARDENING,
RELEASE_SEQUENCE, issue-18-handoff, public-command-entry and actual AppDelegate,
first-run, migration, command-server, receiver and embedded launch code.
The public command already implements open/stdin/wait; old placeholder wording
is historical. Apple-anchor/team validation deliberately refuses unsigned cold
launch and must remain unchanged. A warm private endpoint can accept unsigned
hosted development code. AppDelegate starts the listener only from ordinary
launch after welcome dismissal. A first-launch CLI request may therefore fail
while the welcome is visible. This is a source hypothesis, not a native finding.

## Narrow pre-implementation probe

No production app, CLI, security check, dependency/pin or release guard changes.
Build the actual locked Release app and embedded helper, and a standalone small
AppKit controller from reviewed source. Run only on the actual GitHub macOS26
ARM runner, in its existing disposable user session and RUNNER_TEMP. Refuse
other hosts, existing product instances, existing fixture roots or unexpected
bundle identity/path. The controller uses NSWorkspace's ordinary app launch,
without XCTest/UI-test arguments, preference-domain substitution, endpoint
redirection or signature exceptions. Record actual PID, executable, bundle and
launch-date identity. All termination actions revalidate those identities.

First preserve the absent/present first-run key in the real fresh runner domain,
launch normally, record the real app identity, and execute a file request through
the public user-bin symlink. Preserve its exact result and diagnostics. This is
a first-run observation, not a reason to skip that journey if it fails.
Then normally terminate this clean synthetic installation, explicitly configure
ONLY the existing first-run-completed key in that runner domain, and relaunch
the SAME app bytes. Label this configured-installation comparison honestly.
Require actual warm file success, missing-file failure, a real --wait process
that stays alive and returns success after normal app termination. Relaunch and
require actual UTF-8 piped Markdown success and malformed UTF-8 rejection.
Preserve all fixture source bytes. No fake server or protocol injection.

## Ownership, failure and evidence

The Python orchestrator owns bounded child commands, fixture files/symlink and
receipts. The small MainActor AppKit controller owns normal launch/termination,
with no cross-module product dependency or public API. Use the existing owned
600-second executor unchanged; each command has its own finite process bound.
A normal-quit refusal fails the wait comparison, never counts as success. Final
cleanup of an app holding synthetic unsaved stdin may force-terminate only the
same freshly launched PID/path/launch-date instance; that cleanup is not native
Quit acceptance. Never delete/rewrite product endpoints or owner state.

Record the full MacDown2 and orchestration source file keyset/hashes, all24pins,
actual app/helper binary hashes and public symlink target, command outputs/exits,
app identities, first-run preferences, normal-wait completion and cleanup mode.
Always upload first results and owned status even on failure. Overall probe must
fail if first-run or a comparison fails; comparison successes do not waive it.
No repeated unchanged native run. Any observed defect needs a written source
correction and exact baseline/candidate proof before production integration.

## Verification sequence and limits

Locally inspect source, compile the standalone helper without executing it,
syntax-check orchestration/workflow, run existing ownership controls and ordinary
compliance/inventory. Hosted execution is the first native outcome. A draft PR
registers the new PR-triggered workflow; do not merge a failed diagnostic probe
as a product fix. Current combined Preview PR108 stays separately blocked.
Cold Apple-trusted launch, signing/notary, dirty-close cancel/Save As, persistent
stdin fidelity, full protocol corpus, migration/update and owner UI journeys
retain their original owning criteria. No release/publication authorization is
inferred from this narrowly controlled warm comparison.

## Preserve the first refusal and observe actual startup readiness

First source1515733e run42297310075 actually launches the normal Release app,
then the fresh file command returns5 without a timeout. The clean app normally
terminates. After explicitly setting the existing first-run key, a second actual
launch still has no endpoint within the unchanged10s bound, so configured
file/stdin/wait checks do not run. Its same PID/path/launch-date cleanup succeeds.
All1588source hashes/24pins, actual synthetic checkout tree, app/helper digests,
owned normal1 status and unchanged synthetic source bytes are independently
verified. Welcome alone is NOT a sufficient diagnosis. Keep the first full job,
receipt, commands and unexecuted comparisons; no source fix follows from it.

A new diagnostic must distinguish migration/readiness from listener/endpoint
failure. Keep production source, Release configuration, signing/cold-launch
policy, launch arguments, original10s bound and every acceptance criterion
unchanged. Extend only the hosted harness/controller to capture actual window
metadata for its identity-bound PID using CoreGraphics' ordinary window list
(no screenshot, accessibility automation or permission bypass), a bounded
same-PID stack sample, bounded unified log output and no-follow metadata under
the runner's fixed first-party Application Support roots. Before launch, record
whether those roots already existed; never delete or rewrite them. Copy only
bounded JSON migration records from the newly generated MostlyText root; do not
read other application stores or credential domains. Record the real first-run
key after configuration, using defaults read, to distinguish failed persistence.
Do not write any app model, override domain/endpoint, dismiss a window or start
a listener from the harness. Captures happen after the original refusal/deadline,
are labelled failure observations and never decide success. Each external capture
has a finite bound and its raw refusal is retained. Missing window titles or log
permission are missing evidence, not an empty/ready app verdict. Keep all
criteria, no unchanged retry and no diagnostic-branch merge as a production fix.

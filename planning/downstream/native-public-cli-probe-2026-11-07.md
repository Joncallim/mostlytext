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

## Completed observation: distinguish the optional import's actual outcome

Source54c89e62 run42299346842 completes with the same actual refusal in both
launches. Both real same-PID window lists identify MostlyText Migration. Fresh
storage roots were absent before launch; the actual installation plan, preferences,
complete and managed-path markers now exist, all user-owned/private, with no
preserved development source. The optional original-editor journal has only its
lock. Both samples show an idle AppKit event loop, not a blocked parser call.
First-run persistence reads back1. These facts narrow investigation past the
whole-install transaction but do not identify optional review versus refusal or
a lost ready callback. No permission or migration-policy relaxation follows.

Use a named derived diagnostic build to observe existing transitions and errors.
A new source-preparation script runs ONLY on the hosted checkout, validates the
exact original bytes of three tracked files and prepares all edits before writing.
Add environment-gated Foundation NSLog observations to LegacyImportStartup,
ApplicationMigrationStartup and AppDelegate: journal/bootstrap/resume/source
entry count, existing phase changes, finish/callback availability, and caught
error TYPE plus system error domain/code. No preference values, paths, document
text, extra source read, model write, scheduling, skip, guard or policy changes.
Existing operation calls and error handling remain in the same order. The normal
launcher explicitly supplies only the trace flag; no domain/endpoint or test-host
argument is added. The original10s acceptance bounds and all6 criteria remain.

This is transparently instrumented source, not an unchanged shipping app. Record
canonical Git blob hashes AND every executed source hash, the precise three-file
before/after delta and original/replacement fragments. Upload the overlay recipe
and all native output even on failure. Independent verification reconstructs the
three executed files from canonical Git source and refuses missing/extra changes.
Never retarget the earlier normal Release receipts, qualify original1515/54c8 or
merge this diagnostic overlay as a production fix. Locally run pure preparation
controls and unsigned compile-only of the observed sources; no owner execution.
The next hosted first outcome must give the actual optional-import disposition
before any product correction. Ordinary production source on main is unchanged.

## Retain missing log observations; use a private bounded phase record

The first derived source5359e664 run42303506526 completes with both endpoint
refusals. Its exact three-source recipe is retained, but neither captured unified
log contains a MOSTLYTEXT_STARTUP event. The requested phase observation is
therefore unqualified: do not infer a ready, blocked or review state from silence,
attribute an error, or patch startup from this result. Keep its first artifact.

Replace the observation output mechanism, not application policy. The same three
source overlays now append small JSON phase records to the precreated private
fixture file /Users/runner/work/_temp/native-cli-proof/startup-events.jsonl. The
derived observer checks the actual runner home, opens only that fixed existing
file with no-follow/append/nonblocking flags, requires a regular single-link
0600 file owned by the executing UID, and refuses growth beyond64KiB. One
bounded record includes only component, phase/event, PID and time. The harness
creates it exclusively before app launch and retains it as an artifact. It is
not a preferences, endpoint, document or user-selected path. This exists only
in explicitly recorded derived diagnostic source; shipping main is untouched.
Keep NSLog as supplementary output, but file-event presence is the required
positive before claiming phase visibility. No new source read, scheduling,
callback, readiness guard, consent, first-run choice or deadline change. Native
phase evidence, not silent logging, must select the next production correction.

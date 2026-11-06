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

# Keep non-document queued paths from suppressing Welcome

## Owner summary

Show Welcome when the app has no real document or folder launch request. A bare
session-directory argument or other queued non-file must not skip onboarding.
The ready open-files handler already deliberately ignores those paths. Apply
that same regular-file rule to the first-run decision and retain all raw queued
paths for normal late resolution. No setting, import or launch-isolation policy
changes. This is a bounded #17/#5/#16 remediation, not final release acceptance.

## Baseline and concrete evidence

Actual maincc1cd1e6da16f43b268b2b9cc03b155f1b6d54d9 includes qualified startup,
status, SDK calibration and licence work. Product bytes remain those from full
CI42343094450. The first original38-method matrix42350228707 at ec2d includes
a genuine failure in FirstRunUITests.testOpenSampleDocumentDismissesWelcomeAndOpensTheSampleText,
line61: Welcome never appears before any sample action. Actual hierarchy shows
Untitled. Exported original test-manager diagnostics confirm -UITesting,
-sessionDir and -ForceFirstRun with a fresh private directory. The framework
subsequently restarts, so the batch correctly stops and leaves the following
two methods NOT_RUN. No first outcome is rewritten as a pass.

The actual AppDelegate ready-handler comment explicitly explains that AppKit
routes bare session-directory values and folder drops through openFiles. That
handler and pending-session decision use regularDocumentURLs. The first-run
branch still tests startupOpenFiles.isEmpty, so an invalid/directory queue can
suppress Welcome even though it opens no document. This is a concrete source
policy inconsistency. Actual historical raw callback queue bytes were not
captured; it is a supported hypothesis about the observed failure, not proof
of its sole cause. Do not claim an argument trace proves the callback payload.

## Scope, ownership and invariants

Change only AppDelegate's startup decision: compute whether the queued paths
currently admit any regular document using the same existing helper. Use that
boolean for both Welcome eligibility and pending restore. Preserve the raw queue,
existing launchURLs/launchFolderURL priorities, symlink late resolution, regular
file opens, current-domain/migration/once-only listener and protected test guards.
Do not alter original UI methods, assertions, waits, positives or formats.
No new model, cross-module dependency, preference or public API is needed.

Before code, retain the first actual result and source discrepancy. Run a small
Foundation/Darwin console that extracts the literal original/new first-run
condition and regular-file helper plus the exact existing URL extension. Use
real owned temporary files/directories/missing/dangling/linked/removed paths;
include non-first-run, explicit-file and explicit-folder controls. The original
condition must expose the policy counterexample and the correction must pass
without AppKit or owner data. Do not present this as AppKit delivery acceptance.

## Qualification and stop conditions

Preserve all ten complete first matrix outcomes before publishing another
matrix source. Keep this one-epic unit as a real local branch/merge parent;
assemble it into the corrected matrix candidate without a duplicate standalone
native attempt. First changed-source execution must retain original FirstRun
and all other38 methods, genuine positives, exact identities and owned results.
Require complete current CI, all affected source/native checks and independent
input/result/tree review before integration. Any continuing welcome failure
requires its actual diagnostics and a new architectural decision, not an
unchanged retry, hidden callback, increased deadline or weaker expectation.

Strict format/lint and literal-source controls are local non-launch evidence.
No CORTANA app build/registration, GUI/model/runtime, private signing key or
separate account is used. Final locale/VoiceOver, installation, protected-owner
and exact signed-artifact gates remain distinct. Whole issue contracts stay
open unless every original criterion is independently satisfied.

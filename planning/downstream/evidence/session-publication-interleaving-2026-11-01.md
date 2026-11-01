# Control the session-publication test interleaving

## Owner summary

The dirty-edit termination test used real startup file monitoring without waiting
for its initial observation. A coordinator-save drain does not drain the nested
monitor callback tasks. The fixture now waits for observation handling and its
resulting startup save before entering the controlled recovery gates. Documents
and Recovery use sibling directories, so creating recovery data cannot itself
signal the watched document directory. No publication guard or retry is relaxed.

## Preserved failure and discriminating control

Hosted CI [41283272983](https://github.com/Joncallim/macdown_2/actions/runs/41283272983)
on export head `872c800bff70801380ab1d3b6ab32a6f35272101` failed the three
final publication assertions: persisted false, publication count zero and no
recorded recovery epoch. Its recovery-buffer check had passed. The raw log is
retained on CORTANA under CORTANA-Builds/reconcile-20261101-issues/
pr532-job-failure.log. The older integration run 40281269838 at `e57a71d5`
also failed this test before the ordinary-export PR was merged.

Source review identifies a concrete competing transition: applying the unchanged
baseline disk snapshot to dirty text advances its mutation generation and calls
scheduleSaveSession. That invalidates a captured session. The existing recovery
hook counts every coordinator save, so an uncontrolled startup autosave can also
consume a gate intended for termination. The old log did not record the callback
or rejection reason; it does not establish which transition occurred there.

The test now has two controlled cases. Without the competing observation, it
requires one publication of the latest edit. With baseline observation delivered
at the second recovery gate, it requires generation advancement, zero canonical
publications and a superseded/changed-document rejection. This preserves the
expected safe failure instead of extending retries or accepting stale state.
The prior diagnostic hook records rejection reasons on a future failed assertion.

## Validation and limits

Independent source re-review and [exact-head CI 41289671790](https://github.com/Joncallim/macdown_2/actions/runs/41289671790)
passed at `31344a7c8d9c9fb70958ba839eca5b80614ac162`. Implementation merge
`54e78ab5f77fada6482587428bc1a5ad96429ecb` has the same tree. The run passed
3,038 package tests in 417 suites with the two existing Neon known issues,
and 535 app tests in 110 suites. Both dirty-edit cases executed successfully,
as did repeated invalidation. Debug/Release app and CLI builds, test compilation,
lint, Compliance and dependency-lock checks passed.

Two additional failed attempts remain preserved. Run 41285945707 failed app-test
compilation because FileEncodingMetadata was passed instead of String.Encoding;
6eeefaf2 projects its encoding and carries its BOM. No app-case pass is claimed
from that attempt. Run 41288423185 exposed the older offscreen viewport test's
150 ms assumption: selection and viewport passed, but the pending snapshot was
not yet consumed. 31344a7c requires and awaits the actual frame-sync task and
retains its scroll view through unchanged assertions. That case passed in the
final package run. Neither production timer delays nor assertions were relaxed.
Raw logs are retained beside pr532-job-failure.log as
pr533-first-full-failure.log, pr533-package-failure.log and pr533-final-job.log.

No local app or native UI journey was executed. This fixes fixture ownership of
the controlled schedule; it does not claim every historical session failure is
explained, remove the deliberate metadata transition, or close #183/#115.

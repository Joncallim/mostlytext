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

Independent source review and exact-head hosted CI are required before integration.
No local app or native UI journey was executed. This fixes fixture ownership of
the controlled schedule; it does not claim every historical session failure is
explained, remove the deliberate metadata transition, or close #183/#115.

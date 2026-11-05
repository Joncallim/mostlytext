# Cancel diagram preparation at its actual suspension point

## Owner outcome

Test that cancellation retires an unpublished real WebKit page before its borrower
returns. Keep production admission/evaluation deadlines and the five-second test
bound on cancellation cleanup unchanged. A cold navigation delay must not prevent
the test from reaching the operation it is supposed to verify.

## Observed failure and scope

Post-merge CI 42101684271 on `05238f47191e8350f4ace5817a5f6066e1394176`
fails one of 3,622 package tests. `cancelledPreparationRetiresBeforeTheBorrowerReturns`
does not obtain `probe.page` within its five-second polling setup. The immediately
preceding preparation tests and subsequent cold/admission/evaluation controls pass.
The same source tree passed the complete PR92 run. Preserve both results.

The pool's production admission contract allows fifteen seconds for queueing and
cold navigation, separately from the evaluation timer. The test's shorter setup
poll therefore fails before cancellation is requested. This establishes an
incorrect test synchronization boundary, not the reason WebKit was late or closure
of issue #15's broader extended-session hang investigation.

## Binding test correction

The existing preparation probe signals a checked continuation when the real public
factory enters its preparation closure. If the borrower fails admission before
that point, forward the actual failure to the waiter; do not retry or ignore it.
Cancel only after that signal. Keep an explicit five-second watchdog on borrower
cancellation, require CancellationError, require the page already terminated, and
also require that the borrower body never received it. Always cancel/drain the
borrower and shut down the pool if setup throws. The public factory, real WebKit,
retirement code and all production deadlines remain unchanged.

All actual native tests compile locally only and must execute on hosted macOS 26.
Complete CI retains all original admission/evaluation/cold-page controls. A
successful rerun is evidence for this test correction, not final renderer budget
calibration or protected-account native acceptance.

# PDF export cancellation checkpoints — 9 November 2026

## Owner summary

Cancelling a PDF export while WebKit is still loading should return promptly.
If cancellation or document closure happens while macOS is printing, the output
must be discarded before validation or publication. This change makes those two
checkpoints explicit. It does not add a whole-export progress display or a time
limit around the synchronous macOS print operation; those remain required by
[MostlyText #11](https://github.com/Joncallim/mostlytext/issues/11).

## Baseline and decision

The implementation baseline is `ffe692feef9c7c8f45ccd2dea1f88e31115aeae6`.
`PDFExportAdapter` already bounds WebKit page loading and the vector snapshot
fallback at 30 seconds each. `ExportLifetimeLease` blocks publication after
document closure, and the destination admission publishes only checked bytes.
However, the page-load continuation previously ignored task cancellation until
WebKit completed or its watchdog fired. After `NSPrintOperation.run()`, the
adapter previously read and validated the generated PDF before the next
cancellation/lease check.

The adapter now stops page loading and resumes its continuation with
`CancellationError` when the owning task is cancelled. It also checks task and
document lifetime immediately after `run()` returns, before reading the print
scratch file. If `run()` returned false and the task was cancelled, cancellation
takes precedence over a misleading print failure. Temporary print/snapshot
files remain in the existing `defer` cleanup; the publication cutoff remains
unchanged.

The existing comment claimed AppKit supplied a print progress panel with
Cancel. Apple's [progress-panel documentation](https://developer.apple.com/documentation/appkit/nsprintoperation/showsprogresspanel)
states that PDF/EPS generation displays no such panel regardless of the flag.
The flag remains true to preserve the working print-operation configuration,
but it is not treated as user feedback for PDF/EPS generation.
Apple's [`run()` documentation](https://developer.apple.com/documentation/appkit/nsprintoperation/run())
states it runs on the current thread. In this adapter that is the main actor;
task cancellation cannot interrupt an already-running synchronous print pass.

## Verification and remaining work

The existing dedicated Release PDF qualification selects the entire adapter
suite plus two controlled cancellation tests. An already-cancelled navigation
must produce `CancellationError` rather than waiting for WebKit or its 30-second
watchdog. A failed print result with a revoked document lease must report
cancellation, leave pre-existing output byte-for-byte intact, and retire scratch
files. The latter is a controlled print-result seam, not evidence of interrupting
AppKit mid-print. The exact-source and result verifier requires all eleven
functions to pass without skips or expected failures. Ordinary builds compile
the tests but do not run the guarded native PDF selection in an owner account.

Before #11's complete-operation criterion can be checked, a separate design
and test unit must show visible progress from preparation through publication,
measure the synchronous print phase on representative and adversarial Release
documents, and establish a correct user cancellation policy for that phase.
The test-account native journey must verify panel responsiveness, Cancel,
normal Quit, and preservation of any prior destination. A hosted test or source
check alone cannot establish that user-visible behavior. No print timeout or
whole-export progress claim follows from this checkpoint change.

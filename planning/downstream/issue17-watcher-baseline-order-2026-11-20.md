# External watcher baseline ordering — 20 November 2026

The external-file controller launches same-file baseline updates as independent
tasks. Before this fix, each task retained the encoding and file identity from
the moment it was scheduled. A held older task could run after a newer one and
restore an obsolete decoding policy. A same-file update could also reach the
monitor before its queued first bind; that update returned without effect, and
the bind then installed its captured old policy.

The controlled app-target tests use the production `ExternalFileController` and
`DocumentFileMonitor` with a real UTF-8 file. They hold each queue point,
replace the live document policy, release the held work, and read the monitor's
actual decoded snapshot. On pre-fix head `aaf5b9bc`, [hosted CI
44558899328](https://github.com/Joncallim/mostlytext/actions/runs/44558899328)
failed both new tests with four assertions: the snapshot was `cafÃ©`, decoded
as Latin-1, instead of UTF-8 `café`. The other 3,967 package tests passed.

Product commit `21bd072c` retires superseded same-file update tasks and checks
the live document, binding generation and update sequence immediately before
calling the monitor. The first bind reads the current document after its queue
point and refreshes the policy after installation, covering an update that
reached the monitor before it was bound. Disposal and a new binding cancel the
old baseline task. [Corrected CI
44568994776](https://github.com/Joncallim/mostlytext/actions/runs/44568994776)
passes 3,967 package tests and 789 non-UI app tests; the targeted Debug
controller job passes 23 tests, including both new regressions. A local locked
Debug build-for-testing passed without launching the app. Focused lint and
ordinary compliance pass.

The first targeted Release job was canceled before runner acquisition due to
hosted macOS capacity; it did not produce a Release verdict. The exact-head
rerun belongs to [PR #310](https://github.com/Joncallim/mostlytext/pull/310).
The tests prove these controlled controller/monitor schedules, not a full
native Finder/FSEvents timing or deletion-after-rebind matrix. #12, #17 and
the private release-candidate gate remain open.

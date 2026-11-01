# Release FileCore measurements, 1 November 2026

These are component measurements for #119. They use the unchanged FileCore
sources identified by every digest in `source-manifest.json`, a Foundation-only
executable, and newly created 0700 temporary fixtures on the internal disk.
No application, document controller, GUI, real user document or recovery store
was started or read. The source manifest still matches integration candidate
`6a7329c940437b5bd5491b3454fd0e4b9df26ea4`.

Environment: CORTANA, Apple M3 Pro, 18 GiB memory, macOS 26.5.1 (25F80),
Xcode 26.6 (17F113). Build configuration is Release. The files were freshly
written and then read repeatedly; this is not a cold-cache storage benchmark.
Every timed revision/snapshot read asserts that it runs off the main thread and
verifies the exact expected SHA-256/size. No minimum-of-runs selection is used.

## All three runs

Each run retains all 30 revision/digest samples and 30 decoded snapshot samples
per size. The table shows conventional medians and maxima in milliseconds.

| Run | Bytes | Revision median / max | Snapshot median / max |
| --- | ---: | ---: | ---: |
| 1 | 1,000,000 | 0.592 / 3.005 | 3.631 / 5.023 |
| 2 | 1,000,000 | 0.547 / 1.658 | 3.645 / 3.753 |
| 3 | 1,000,000 | 0.552 / 1.573 | 3.643 / 3.724 |
| 1 | 10,000,000 | 5.134 / 5.323 | 35.975 / 43.350 |
| 2 | 10,000,000 | 5.046 / 5.202 | 35.463 / 36.568 |
| 3 | 10,000,000 | 5.155 / 5.452 | 36.071 / 36.426 |

The JSON records include every value, p95, five real atomic-write delivery
samples per size/run, actual completed/cancelled debounce waits and request
generation traces. Timing ends at the monitor's matching snapshot callback,
not at application/controller reconciliation or editor layout.

| Bytes | Write-start to matching observation, all 15 samples | Actual completed 150 ms debounce waits |
| ---: | ---: | ---: |
| 1,000,000 | 157.720–161.222 ms | 150.130–154.073 ms |
| 10,000,000 | 189.139–208.555 ms | 150.058–154.363 ms |

Writes, vnode delivery, queueing, hashing and decoding remain included in the
first column. The actual sleeps are recorded separately; subtracting a nominal
150 ms is not presented as an app-latency measurement.

## Idle and follow-up observations

After awaited initial binding, every untouched one-second baseline interval had
zero additional observations and zero scheduled debounce waits. This measures
component callbacks/scheduling only. It does not establish the native app's
periodic CPU/power wakeup budget or count monitors per window.

The initial exploratory driver incorrectly labelled the one-second interval
immediately after a matching write callback as idle. That interval contained one
additional observation for both sizes. It is retained, not discarded. The final
three runs distinguish the untouched baseline from the post-write tail and retain
the complete generation trace; five of the six post-write windows contain one
additional callback. For example, run 1 records generations 20 and 21 after its
last replacement. The current monitor rearms watches after replacement and can
emit a fresh probe under a new request generation. That source behavior is
consistent with the trace, but this experiment does not identify historical
#183 session-publication failures or prove the absence of OS idle wakeups.

The monitor currently owns a parent-directory event source and a file event
source. Native per-window resource accounting and any older watcher-count wording
still need reconciliation; these timings do not certify that separate row.

## Reproduction and retained failures

`PerfProbeMain.swift` is the exact final driver. Copy it beside every unmodified
`MacDown2/Packages/MacDownKit/Sources/FileCore/*.swift` file into one temporary
SwiftPM executable target, with tools version 6.2 and macOS 26. Build/run with
`swift run -c release --package-path <temporary-package>`, then run the same
Release executable twice more. Do not launch the app or substitute real files.
The driver creates and removes only its own UUID-named temporary directory.

The full work directory is `CORTANA-Builds/external-file-perf-20261101` on the
Fast SSD. It retains the initial compile failure (a non-Sendable Any dictionary
crossed the detached-task boundary), the correction to return serialized Data,
the initial exploratory result and all final build/output files. The initial
summary used the upper middle value for an even sample count; the final driver
uses the conventional median. Original raw samples remain intact.

`validation.json` binds the final driver/results, source digests and environment.
These data add Release component evidence. #119's full native matrix, event-to-
controller reconciliation, idle wakeup profiling and exact candidate acceptance
remain open.

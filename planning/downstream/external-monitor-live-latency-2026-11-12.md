# External monitor latency measurement — 12 November 2026

## Scope

This probe measures the production `DocumentFileMonitor` with its real
`LiveDocumentDirectoryWatcher`, 150 ms debounce, detached `DocumentFileProbe`
and `FileStore` snapshot/digest path. Each of three fresh cases at each size
prewrites a same-directory replacement, binds a watcher to an equally sized
source, then times from just before an atomic `rename` through the matching
SHA-256 observation. It also times three direct snapshot/digest reads per
case. The test verifies final on-disk bytes and the full observed digest. It
does not launch MostlyText or measure the editor controller, paint or UI.

## Local optimized Release result

Source: `main` at `4478bf0845c1b7d9e36248d73fb4718a8c7bf75a` plus the
single test in this change. Host: Apple M3 Pro, macOS 26.5.1, Xcode 26.6.
Command from `MacDown2/Packages/MacDownKit`:
`swift test -c release --force-resolved-versions --filter DocumentFileMonitorReleaseLatencyTests --no-parallel`.
The one test passed with six real watcher observations and no timeout.

| UTF-8 source bytes | Direct snapshot/digest reads, ms (nine samples) | Rename start to matching observation, ms (three samples) |
| ---: | --- | --- |
| 1,000,000 | 5.267, 3.317, 3.333; 5.801, 5.171, 4.835; 8.325, 6.712, 5.795 | 158.522, 162.260, 162.113 |
| 10,000,000 | 43.409, 33.290, 32.798; 32.609, 31.733, 31.194; 33.228, 33.160, 32.934 | 193.365, 199.864, 184.482 |

The reported event interval includes the configured 150 ms debounce, kernel
notification, dispatch, disk read, digest, decode and callback. `rename` itself
took 0.095–0.119 ms in these cases. The probe does not timestamp the kernel
event independently or subtract debounce to claim a separate scheduling time.

The same final-source test also passed in Debug on this host. Its direct read
samples were 5.24–10.28 ms at 1 MB and 50.01–59.93 ms at 10 MB;
rename-start-to-observation was 162.60–165.98 ms and 217.52–220.68 ms
respectively. These are observed
fixture ranges, not a product performance ceiling.

## Remaining #12 evidence

The exact Release-candidate manual external-file matrix, controller-level
reconciliation and selection/scroll behavior, idle wakeups, watcher occupancy
and whole-app task growth remain open. The test records a repeatable component
measurement and protects actual watcher delivery and final-byte identity; it
does not turn those separate acceptance rows into a pass.

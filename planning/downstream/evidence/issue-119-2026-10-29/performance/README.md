# Executed serial FileCore measurements, 2026-10-29

The optimized arm64 FileCore component matrix completed: 126 serial processes, 426 validated calls (120 fresh-process, 300 warm, six priming), no failures or resource-guard triggers. Each operation/size cell uses 20 fresh processes and one process with one priming call followed by 50 warm calls. Priming is excluded from the table. Percentiles use nearest rank. The Swift source and Python driver here are exact copies of what ran; original paths and process IDs remain in the raw records.

Hardware: Mac15,6, 18 GiB, 11 logical/physical CPUs; macOS 26.5.1 (25F80), APFS on /System/Volumes/Data, SDK 26.5. The linked module was built with Release `-O -whole-module-optimization -enable-testing`; the harness also used `-O`. See provenance.json for source head, the one-line FileCore patch and executable/framework/lockfile hashes. These are private acceptance-build measurements, not shipping-signature evidence.

| MiB | Operation | Population | n | p50 ms | p95 ms | max ms | Process peak MiB |
|---|---|---|---:|---:|---:|---:|---:|
| 1 | snapshot | fresh process, cache uncontrolled | 20 | 7.876 | 8.911 | 9.170 | 11.75 |
| 1 | snapshot | warm process | 50 | 3.244 | 4.444 | 4.837 | 11.91 |
| 1 | revision | fresh process, cache uncontrolled | 20 | 2.140 | 2.396 | 2.561 | 10.77 |
| 1 | revision | warm process | 50 | 0.516 | 0.618 | 0.626 | 11.00 |
| 1 | probe | fresh process, cache uncontrolled | 20 | 4.915 | 5.127 | 5.189 | 11.70 |
| 1 | probe | warm process | 50 | 3.373 | 3.559 | 3.575 | 11.94 |
| 10 | snapshot | fresh process, cache uncontrolled | 20 | 34.836 | 35.533 | 35.824 | 29.73 |
| 10 | snapshot | warm process | 50 | 32.433 | 33.552 | 33.826 | 30.03 |
| 10 | revision | fresh process, cache uncontrolled | 20 | 9.099 | 10.021 | 10.075 | 19.73 |
| 10 | revision | warm process | 50 | 5.380 | 6.836 | 7.507 | 20.02 |
| 10 | probe | fresh process, cache uncontrolled | 20 | 34.167 | 34.938 | 35.117 | 29.77 |
| 10 | probe | warm process | 50 | 32.785 | 34.157 | 34.328 | 30.03 |

`snapshot` measures FileStore.readSnapshot (owned-byte read, stable metadata, SHA-256, decode); `revision` measures FileStore.readRevision (read, metadata, SHA-256, without decode), not isolated hashing; `probe` measures the real internal DocumentFileProbe.observe async path. Calls run serially inside a detached utility worker. Snapshot/revision calls use an autorelease pool. Returned summaries retain no file/string payload between calls.

The inner API timer excludes result-summary construction, validation, memory sampling and output. `outerDetachedNanoseconds` additionally covers worker scheduling and summary creation. Raw records retain both. Fresh-process reads have **uncontrolled filesystem cache**: fixture generation and hashing warm it. No cache eviction was attempted and no result is labelled cold storage.

Peak is Darwin getrusage's lifetime high-water RSS for the whole process, including startup, logging and previous calls. TASK_VM_INFO before/after endpoints can miss transient allocations; neither metric proves retained memory per operation. Driver peakObservedRSSKiB is a sampled guard only; zero means no sample captured before the child exited, not zero memory. Per-child 20-second and sampled 512-MiB guards never fired. A missed fast-child sample cannot establish a strict peak ceiling.

This does not prove native publication latency, a 300-ms application budget, foreground responsiveness, MainActor I/O absence, idle activity, watcher/descriptor lifetime, multi-window behavior, event-storm bounds, one-active/one-pending admission, or a shared four-worker limit. Those gates remain open. No application pass threshold is invented from these component timings.

## Reproduce

Use a completed locked optimized FileCore build with testability enabled, then compile Harness.swift with Swift 6, `-O -parse-as-library -target arm64-apple-macos26.0`, the macOS 26.5 SDK, `-I` to Release, `-F` and rpath to Release/PackageFrameworks, and `-framework FileCore`. The historical products were `/tmp/mt119-scroll-reload-derived/Build/Products/Release`. `@testable import FileCore` admits the real internal prober.

Create owned fixtures by repeating the UTF-8 bytes `Bounded external-file measurement fixture, ordinary UTF-8 text and short lines.\n` and truncating to exactly 1048576 or 10485760 bytes. Independently verify the digests in fixtures.json, and change its paths to the new owned locations. Copy the compiled executable to `harness` beside run.py. Run `python3 run.py` serially with no competing native/build lane. Retain first failures; the supplied driver stops at one. It writes raw/*.jsonl, per-process stderr, run-manifest.json and summary.json. The committed raw.jsonl concatenates the original files in manifest order without changing their records. All original stderr files were empty.

Harness CLI: `harness snapshot|revision|probe PATH --expected-size BYTES --expected-sha256 HEX (--once | --warm-count N)`. The driver is a retained experiment script, not a product entry point or a new product admission policy.

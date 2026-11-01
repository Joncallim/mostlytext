import CryptoKit
import Foundation
import Synchronization

struct ObservationRecord: Sendable {
    let time: ContinuousClock.Instant
    let digest: String?
    let requestGeneration: UInt
}

struct SleepRecord: Sendable {
    let start: ContinuousClock.Instant
    let end: ContinuousClock.Instant
    let requested: Duration
    let cancelled: Bool
}

final class Recorder: Sendable {
    let observations = Mutex<[ObservationRecord]>([])
    let sleeps = Mutex<[SleepRecord]>([])

    func observe(_ context: DocumentFileObservationContext) {
        let digest: String?
        if case let .available(snapshot) = context.observation { digest = snapshot.revision.sha256 } else { digest = nil }
        observations.withLock {
            $0.append(.init(time: .now, digest: digest, requestGeneration: context.requestGeneration))
        }
    }
}

@main
struct FileCorePerfProbe {
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func summary(_ values: [Double]) -> [String: Any] {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return ["samples_ms": values, "median_ms": median,
                "p95_ms": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
                "max_ms": sorted.last ?? 0]
    }

    static func measure(_ url: URL, bytes: Data) async throws -> [String: Any] {
        let expected = digest(bytes)
        let store = FileStore()
        var revisions: [Double] = []
        var snapshots: [Double] = []
        for _ in 0 ..< 30 {
            precondition(!Thread.isMainThread)
            let start = ContinuousClock.now
            let revision = try store.readRevision(from: url)
            revisions.append(milliseconds(start.duration(to: .now)))
            precondition(revision.sha256 == expected && revision.fileSize == bytes.count)
            let snapshotStart = ContinuousClock.now
            let snapshot = try store.readSnapshot(from: url)
            snapshots.append(milliseconds(snapshotStart.duration(to: .now)))
            precondition(snapshot.revision.sha256 == expected && snapshot.text.utf8.count == bytes.count)
        }
        let recorder = Recorder()
        let monitor = DocumentFileMonitor(
            debounce: .milliseconds(150), watcher: LiveDocumentDirectoryWatcher(), prober: DocumentFileProbe(),
            sleeper: { duration in
                let start = ContinuousClock.now
                var cancelled = false
                do { try await Task.sleep(for: duration) } catch { cancelled = true }
                let record = SleepRecord(start: start, end: .now, requested: duration, cancelled: cancelled)
                recorder.sleeps.withLock { $0.append(record) }
            }
        )
        let bindStart = ContinuousClock.now
        try await monitor.bind(to: url, priorFileObjectID: nil, onObservation: { _ in },
                               onContext: { recorder.observe($0) })
        let initialObservations = recorder.observations.withLock { $0.count }
        let initialSleeps = recorder.sleeps.withLock { $0.count }
        try await Task.sleep(for: .seconds(1))
        let baselineIdleObservations = recorder.observations.withLock { $0.count - initialObservations }
        let baselineIdleSleeps = recorder.sleeps.withLock { $0.count - initialSleeps }
        var events: [[String: Any]] = []
        do {
            for index in 0 ..< 5 {
                var changed = bytes
                changed[0] = UInt8(65 + index)
                let expected = digest(changed)
                let start = ContinuousClock.now
                try changed.write(to: url, options: .atomic)
                let writeEnd = ContinuousClock.now
                var matched: ObservationRecord?
                while ContinuousClock.now < start.advanced(by: .seconds(5)) {
                    matched = recorder.observations.withLock { records in
                        records.first { $0.time >= start && $0.digest == expected }
                    }
                    if matched != nil { break }
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard let matched else { throw NSError(domain: "ProbeObservationTimeout", code: 1) }
                let sleeps = recorder.sleeps.withLock { records in
                    records.filter { $0.start >= start && $0.end <= matched.time }
                }
                events.append([
                    "write_ms": milliseconds(start.duration(to: writeEnd)),
                    "write_start_to_matching_observation_ms": milliseconds(start.duration(to: matched.time)),
                    "debounce_sleeps": sleeps.map { record in
                        ["requested_ms": milliseconds(record.requested),
                         "elapsed_ms": milliseconds(record.start.duration(to: record.end)),
                         "cancelled": record.cancelled] as [String: Any]
                    },
                ])
            }
            let beforeIdle = recorder.observations.withLock { $0.count }
            let beforeSleeps = recorder.sleeps.withLock { $0.count }
            try await Task.sleep(for: .seconds(1))
            let idleObservations = recorder.observations.withLock { $0.count - beforeIdle }
            let idleSleeps = recorder.sleeps.withLock { $0.count - beforeSleeps }
            let trace = recorder.observations.withLock { records in
                records.map { record in
                    ["after_bind_start_ms": milliseconds(bindStart.duration(to: record.time)),
                     "digest": record.digest ?? "unavailable", "request_generation": record.requestGeneration]
                        as [String: Any]
                }
            }
            await monitor.cancel()
            return ["bytes": bytes.count, "read_revision": summary(revisions), "read_snapshot": summary(snapshots),
                    "watcher_atomic_replacement_samples": events,
                    "one_second_untouched_baseline_observations": baselineIdleObservations,
                    "one_second_untouched_baseline_debounce_sleeps": baselineIdleSleeps,
                    "one_second_after_last_matching_observation_callbacks": idleObservations,
                    "one_second_after_last_matching_observation_new_sleeps": idleSleeps,
                    "observation_trace": trace]
        } catch {
            await monitor.cancel()
            throw error
        }
    }

    static func run() async throws -> [String: Any] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileCorePerf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        var results: [[String: Any]] = []
        for size in [1_000_000, 10_000_000] {
            let pattern = "# Test\n\nSample `code` and **bold** text.\n\n"
            let bytes = Data(String(repeating: pattern, count: size / pattern.utf8.count + 1).utf8)
            let exact = Data(bytes.prefix(size))
            precondition(exact.count == size)
            let url = root.appendingPathComponent("sample-\(size).md")
            try exact.write(to: url)
            results.append(try await measure(url, bytes: exact))
        }
        return ["configuration": "Release", "fixture_cache": "freshly written local files; no cold-cache claim",
                "scope": "FileCore component only; no app/controller reconciliation, native UI or OS wakeup-profile claim",
                "timed_read_loops_on_main_thread": false, "results": results]
    }

    static func main() async throws {
        let data = try await Task.detached {
            let result = try await run()
            return try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        }.value
        print(String(decoding: data, as: UTF8.self))
    }
}

import CryptoKit
import Darwin
@testable import FileCore
import Foundation
import Testing

/// Measures the real watcher-to-snapshot path. These observed times are
/// evidence for the named fixture and host, not an asserted product ceiling.
@Suite("Document file monitor Release latency")
struct DocumentFileMonitorReleaseLatencyTests {
    @Test func oneAndTenMegabyteAtomicReplacementsReachTheRealSnapshotReader() async throws {
        for byteCount in [1_000_000, 10_000_000] {
            for repetition in 1 ... 3 {
                try await measureAtomicReplacement(byteCount: byteCount, repetition: repetition)
            }
        }
    }

    private func measureAtomicReplacement(byteCount: Int, repetition: Int) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("mostlytext-monitor-latency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.md")
        let replacement = directory.appendingPathComponent("replacement.md")
        let originalBytes = Data(repeating: UInt8(ascii: "A"), count: byteCount)
        let replacementBytes = Data(repeating: UInt8(ascii: "B"), count: byteCount)
        try originalBytes.write(to: source)
        try replacementBytes.write(to: replacement)
        let originalDigest = SHA256.hash(data: originalBytes)
            .map { String(format: "%02x", $0) }.joined()
        let replacementDigest = SHA256.hash(data: replacementBytes)
            .map { String(format: "%02x", $0) }.joined()

        let store = FileStore()
        var readMilliseconds: [Double] = []
        for _ in 0 ..< 3 {
            let began = DispatchTime.now().uptimeNanoseconds
            let snapshot = try store.readSnapshot(from: source)
            readMilliseconds.append(milliseconds(since: began, until: DispatchTime.now().uptimeNanoseconds))
            #expect(snapshot.revision.fileSize == byteCount)
            #expect(snapshot.revision.sha256 == originalDigest)
            #expect(snapshot.text.utf8.count == byteCount)
        }

        let recorder = TimedSnapshotRecorder()
        let monitor = DocumentFileMonitor()
        do {
            try await monitor.bind(to: source, priorFileObjectID: nil) { recorder.append($0) }
            await waitUntil { recorder.count == 1 }

            let began = DispatchTime.now().uptimeNanoseconds
            guard rename(replacement.path, source.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let renameEnded = DispatchTime.now().uptimeNanoseconds
            await waitUntil({ recorder.timestamp(for: replacementDigest) != nil }, timeout: .seconds(10))
            let observed = try #require(recorder.timestamp(for: replacementDigest))
            #expect(try Data(contentsOf: source) == replacementBytes)
            print("monitor-latency bytes=\(byteCount) repetition=\(repetition) " +
                "read_ms=\(readMilliseconds) rename_ms=\(milliseconds(since: began, until: renameEnded)) " +
                "rename_start_to_observation_ms=\(milliseconds(since: began, until: observed)) " +
                "configured_debounce_ms=150")
        } catch {
            await monitor.cancel()
            throw error
        }
        await monitor.cancel()
    }

    private func milliseconds(since start: UInt64, until end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }
}

private final class TimedSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [(digest: String, timestamp: UInt64)] = []

    func append(_ observation: DocumentFileObservation) {
        guard case let .available(snapshot) = observation else { return }
        lock.withLock {
            snapshots.append((snapshot.revision.sha256, DispatchTime.now().uptimeNanoseconds))
        }
    }

    var count: Int {
        lock.withLock { snapshots.count }
    }

    func timestamp(for digest: String) -> UInt64? {
        lock.withLock { snapshots.first { $0.digest == digest }?.timestamp }
    }
}

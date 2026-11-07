import CryptoKit
@testable import FileCore
import Foundation
import Synchronization
import Testing

@MainActor
@Suite(.serialized)
struct DocumentFileProbeExecutionTests {
    @Test(arguments: [1_000_000, 10_000_000])
    func movedSnapshotReadsAndHashesAwayFromTheMainThread(utf8Bytes: Int) async throws {
        try #require(Thread.isMainThread, "The real probe must be called from the actual main thread")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.md")
        let moved = folder.appendingPathComponent("moved.md")
        let bytes = Data(repeating: 0x61, count: utf8Bytes)
        try bytes.write(to: original)
        let baseline = try await Task.detached { try FileStore().readSnapshot(from: original) }.value
        let identity = try #require(baseline.revision.fileObjectID)
        try FileManager.default.moveItem(at: original, to: moved)

        let threads = ReadThreads()
        let probe = DocumentFileProbe(beforeMovedCandidateRead: { _ in threads.record() })
        let observation = await probe.observe(
            expectedURL: original, priorFileObjectID: identity, decoding: .automatic
        )
        guard case let .moved(snapshot) = observation else {
            Issue.record("The real physical move must yield its actual snapshot")
            return
        }
        let samples = threads.values
        try #require(!samples.isEmpty, "The real moved-file read callback must execute")
        #expect(!samples.contains(true), "External snapshot read and digest must run away from the main thread")
        #expect(snapshot.revision.url == moved.standardizedFileURL)
        #expect(snapshot.revision.fileObjectID == identity)
        #expect(snapshot.revision.fileSize == utf8Bytes)
        #expect(snapshot.text.utf8.elementsEqual(bytes))
        #expect(snapshot.revision.sha256 == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        print("FILE_PROBE_EXECUTION bytes=\(utf8Bytes) callbacks=\(samples.count) mainThread=\(samples.contains(true))")
    }
}

private final class ReadThreads: Sendable {
    private let storage = Mutex<[Bool]>([])

    func record() {
        storage.withLock { $0.append(Thread.isMainThread) }
    }

    var values: [Bool] {
        storage.withLock { $0 }
    }
}

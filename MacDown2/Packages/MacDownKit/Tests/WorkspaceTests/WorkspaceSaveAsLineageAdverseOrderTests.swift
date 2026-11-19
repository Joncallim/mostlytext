@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Handoff regression 3 (#378): an encoding-changing ordinary save is held AT PUBLICATION while a Save As built
/// from the older (pre-change) snapshot queues behind it; the adverse order is then released. The destination's
/// bytes and the returned metadata must follow the accepted lineage, edits made while queued must be what is written,
/// and the Save As destination baseline stays the separately captured one.
@MainActor
struct WorkspaceSaveAsLineageAdverseOrderTests {
    private struct Case {
        let override: FileEncodingMetadata
        let expectedBytes: (String) -> Data?
    }

    private static func makeCase(_ name: String) -> Case? {
        switch name {
        case "latin1":
            Case(
                override: FileEncodingMetadata(encoding: .isoLatin1, bom: .none),
                expectedBytes: { $0.data(using: .isoLatin1) }
            )
        case "utf8-bom":
            Case(
                override: FileEncodingMetadata(encoding: .utf8, bom: .utf8),
                expectedBytes: { Data([0xEF, 0xBB, 0xBF]) + Data($0.utf8) }
            )
        default:
            nil
        }
    }

    @Test(arguments: ["latin1", "utf8-bom"])
    func aSaveAsQueuedBehindAHeldEncodingSaveFollowsTheAcceptedLineage(name: String) async throws {
        let testCase = try #require(Self.makeCase(name))
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("source.txt")
        try Data("café".utf8).write(to: url)

        let barrier = SavePublicationBarrier()
        let heldStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let writer = DocumentWriter(onRequestQueued: { barrier.secondSaveEnteredWriterLane() })
        defer { barrier.cancelAndAllowPublication() }

        let loaded = try FileDocument(fileURL: url, fileStore: heldStore).load()
        let olderSnapshot = loaded.edited(text: "café 1")
        #expect(olderSnapshot.encoding == .utf8Default)
        let destination = directory.appendingPathComponent("copy.txt")

        let encodingSave = Task { try await writer.save(olderSnapshot, encodingOverride: testCase.override) }
        guard await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("The encoding save never reached publication")
            return
        }

        // Built from the OLD snapshot plus an edit made while everything is queued.
        let queuedSnapshot = olderSnapshot.edited(text: "café 2 edited while queued")
        let saveAs = Task { try await writer.saveAs(queuedSnapshot, to: destination) }
        guard await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForSecondSaveToEnterWriterLane() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("Save As never queued behind the held save")
            return
        }
        // While the encoding save is still held, the destination must not exist yet.
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        barrier.allowPublication()
        let encodingResult = try await encodingSave.value
        let saved = try await saveAs.value

        #expect(saved.encoding == testCase.override, "returned metadata follows the accepted lineage")
        #expect(
            try Data(contentsOf: destination) == testCase.expectedBytes("café 2 edited while queued"),
            "destination bytes use the accepted encoding and the text edited while queued"
        )
        #expect(try Data(contentsOf: url) == testCase.expectedBytes("café 1"), "the source keeps its own save")
        #expect(encodingResult.document.encoding == testCase.override)
        await writer.acknowledge(encodingResult)
    }

    @Test(arguments: ["latin1", "utf8-bom"])
    func aQueuedSaveAsCannotOverwriteAFileCreatedAfterDestinationAdmission(name: String) async throws {
        let testCase = try #require(Self.makeCase(name))
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.txt")
        let destination = directory.appendingPathComponent("copy.txt")
        try Data("café".utf8).write(to: source)

        let barrier = SavePublicationBarrier()
        let store = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let writer = DocumentWriter(onRequestQueued: { barrier.secondSaveEnteredWriterLane() })
        defer { barrier.cancelAndAllowPublication() }
        let loaded = try FileDocument(fileURL: source, fileStore: store).load()
        let snapshot = loaded.edited(text: "café 1")

        let first = Task { try await writer.save(snapshot, encodingOverride: testCase.override) }
        guard await waitForSignal(
            timeout: .seconds(30), wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("The first save never reached publication")
            return
        }

        // This is the baseline the Save As panel authorized before the writer
        // lane was available. A later external create cannot become its new
        // implicit baseline merely because the request waited in that lane.
        let second = Task {
            try await writer.saveAs(snapshot.edited(text: "café 2"), to: destination,
                                    destinationBaseline: .absent)
        }
        guard await waitForSignal(
            timeout: .seconds(30), wait: { await barrier.waitForSecondSaveToEnterWriterLane() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("Save As never queued behind the held save")
            return
        }
        let external = Data("external winner".utf8)
        try external.write(to: destination)

        barrier.allowPublication()
        let accepted = try await first.value
        do {
            _ = try await second.value
            Issue.record("Save As overwrote a destination created while it was queued")
        } catch FileStoreError.fileChangedDuringRead {
            // The exclusive destination baseline rejected the external create.
        }
        #expect(try Data(contentsOf: destination) == external)
        #expect(try Data(contentsOf: source) == testCase.expectedBytes("café 1"))
        await writer.acknowledge(accepted)
    }
}

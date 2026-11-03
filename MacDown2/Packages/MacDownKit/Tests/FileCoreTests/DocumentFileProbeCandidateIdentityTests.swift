@testable import FileCore
import Foundation
import Synchronization
import Testing

@Test(arguments: [false, true])
func aMovedCandidateReplacedAfterMetadataDoesNotBecomeTheDocument(_ redirectToOriginal: Bool) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let directory = root.appendingPathComponent("watched", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = directory.appendingPathComponent("original.md")
    let moved = directory.appendingPathComponent("moved.md")
    let retained = root.appendingPathComponent("retained-original.md")
    try "original document".write(to: original, atomically: true, encoding: .utf8)
    let identity = try FileStore().readSnapshot(from: original).revision.fileObjectID
    try FileManager.default.moveItem(at: original, to: moved)
    let calls = Mutex(0)
    let probe = DocumentFileProbe(beforeMovedCandidateRead: { url in
        calls.withLock { $0 += 1 }
        #expect(url.lastPathComponent == "moved.md")
        do {
            try FileManager.default.moveItem(at: url, to: retained)
            if redirectToOriginal {
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: retained)
            } else {
                try "foreign replacement".write(to: url, atomically: true, encoding: .utf8)
            }
        } catch { Issue.record(error) }
    })

    let observation = await probe.observe(expectedURL: original, priorFileObjectID: identity)

    #expect(calls.withLock { $0 } == 1)
    #expect(observation == .missing(original.standardizedFileURL))
    if case let .moved(snapshot) = observation {
        #expect(snapshot.revision.fileObjectID == identity)
    }
    if redirectToOriginal {
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: moved.path) == retained.path)
    } else {
        #expect(try String(contentsOf: moved, encoding: .utf8) == "foreign replacement")
    }
    #expect(try String(contentsOf: retained, encoding: .utf8) == "original document")
}

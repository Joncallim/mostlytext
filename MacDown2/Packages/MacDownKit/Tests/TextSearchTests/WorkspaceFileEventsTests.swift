import CoreServices
import Foundation
import Testing
@testable import TextSearch

@Suite("Recursive workspace events")
struct WorkspaceFileEventsTests {
    @Test func aRootMoveSurvivesFollowingOrdinaryEventsInTheBoundedBuffer() {
        var priority = WorkspaceChangePriority()
        #expect(priority.merge(.changed) == .changed)
        #expect(priority.merge(.rootChanged) == .rootChanged)
        #expect(priority.merge(.changed) == .rootChanged)
    }

    @Test func aRootMoveBeyondTheFirstThousandEventsIsStillClassified() throws {
        var flags = Array(repeating: FSEventStreamEventFlags(0), count: 1025)
        flags[1024] = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        let change = try flags.withUnsafeBufferPointer { buffer in
            try WorkspaceFileChange.classify(#require(buffer.baseAddress), count: buffer.count)
        }
        #expect(change == .rootChanged)
    }

    @Test func aNestedFileChangeReachesTheRootStream() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-events-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("one/two", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try WorkspaceFileEvents(path: root.path)
        defer { source.cancel() }

        try Data("new".utf8).write(to: nested.appendingPathComponent("file.md"))
        let received = await firstEvent(from: source)
        #expect(received == .changed)
    }

    @Test func aChangeInAnAdditionalPhysicalRootReachesTheSameStream() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-events-\(UUID().uuidString)", isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-events-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let source = try WorkspaceFileEvents(paths: [root.path, external.path])
        defer { source.cancel() }

        try Data("external".utf8).write(to: external.appendingPathComponent("new.md"))
        #expect(await firstEvent(from: source) == .changed)
    }

    private func firstEvent(from source: WorkspaceFileEvents) async -> WorkspaceFileChange? {
        await withTaskGroup(of: WorkspaceFileChange?.self) { group in
            group.addTask {
                for await event in source.events {
                    return event
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                source.cancel()
                return nil
            }
            let result = await group.next() ?? nil
            source.cancel()
            group.cancelAll()
            return result
        }
    }
}

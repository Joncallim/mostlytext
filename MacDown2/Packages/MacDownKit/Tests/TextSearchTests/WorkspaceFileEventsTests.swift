import Foundation
import Testing
@testable import TextSearch

@Suite("Recursive workspace events")
struct WorkspaceFileEventsTests {
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

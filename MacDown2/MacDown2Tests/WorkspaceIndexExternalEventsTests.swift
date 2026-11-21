import Foundation
@testable import MacDown2
import Testing
import TextSearch

extension WorkspaceIndexRefreshBehaviorTests {
    @Test func aRecursiveExternalChangeRefreshesTheOpenIndexAndFolderSearch() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let events = ManualWorkspaceEvents()
        let fixture = try await makeController(root: root, eventSource: events)
        defer { fixture.retire() }
        let search = fixture.controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md"])

        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "needle too".write(to: nested.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        events.emit(.changed)

        #expect(await fixture.waitForIndexedPath("nested/b.md"))
        try await waitForSearch(search, paths: ["a.md", "nested/b.md"])
    }

    @Test func aBurstOfExternalChangesCoalescesIntoOneWalk() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let events = ManualWorkspaceEvents()
        let probe = IndexWalkProbe()
        let fixture = try await makeController(root: root, index: probe.makeIndex(), eventSource: events)
        defer { fixture.retire() }
        #expect(probe.count == 1)

        try Data().write(to: root.appendingPathComponent("b.md"))
        for _ in 0 ..< 12 {
            events.emit(.changed)
        }
        #expect(await fixture.waitForIndexedPath("b.md"))
        #expect(probe.count == 2)
    }

    @Test func anExternalDeleteRemovesTheOldSearchTarget() async throws {
        let root = try tempRoot(["a.md", "b.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "needle".write(to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let events = ManualWorkspaceEvents()
        let fixture = try await makeController(root: root, eventSource: events)
        defer { fixture.retire() }
        let search = fixture.controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md", "b.md"])

        try FileManager.default.removeItem(at: root.appendingPathComponent("b.md"))
        events.emit(.changed)
        try await waitForSearch(search, paths: ["a.md"])
        #expect(await Set(fixture.controller.workspaceFileIndex.allPaths().map(\.relativePath)) == ["a.md"])
    }

    @Test func aRetiredRootStreamCannotRepublishIntoTheNextFolder() async throws {
        let first = try tempRoot(["old.md"])
        let second = try tempRoot(["new.md"])
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let oldEvents = ManualWorkspaceEvents()
        let newEvents = ManualWorkspaceEvents()
        let fixture = try await makeController(root: first, eventSource: oldEvents)
        defer { fixture.retire() }
        let controller = fixture.controller
        controller.makeWorkspaceEventSource = { path in
            path == second.path ? newEvents : oldEvents
        }
        await controller.setFileTreeRoot(second)
        #expect(await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath)) == ["new.md"])

        try Data().write(to: first.appendingPathComponent("late.md"))
        oldEvents.emit(.changed)
        #expect(await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath)) == ["new.md"])
        try Data().write(to: second.appendingPathComponent("current.md"))
        newEvents.emit(.changed)
        #expect(await fixture.waitForIndexedPath("current.md"))
    }

    @Test func aRootReplacementRetiresDisplayedResultsBeforeTheNextWalk() async throws {
        let root = try tempRoot(["a.md"])
        let moved = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: moved)
        }
        let events = ManualWorkspaceEvents()
        let fixture = try await makeController(root: root, eventSource: events)
        defer { fixture.retire() }
        let controller = fixture.controller
        #expect(controller.currentQuickOpenOrigin != nil)
        try FileManager.default.moveItem(at: root, to: moved)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        events.emit(.rootChanged)

        #expect(controller.currentQuickOpenOrigin == nil)
        for _ in 0 ..< 200 {
            if controller.folderSearchModel.rootUnavailable {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.folderSearchModel.rootUnavailable)
    }
}

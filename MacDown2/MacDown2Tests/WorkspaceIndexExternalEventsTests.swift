import Foundation
@testable import MacDown2
import Testing
import TextSearch

extension WorkspaceIndexRefreshBehaviorTests {
    @Test func aRealNestedExternalEditRefreshesWithoutWindowActivation() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        controller.makeWorkspaceEventSource = { try WorkspaceFileEvents(paths: $0) }
        await controller.setFileTreeRoot(root)

        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("external".utf8).write(to: nested.appendingPathComponent("new.md"))
        var found = false
        for _ in 0 ..< 500 where !found {
            found = await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath)).contains("nested/new.md")
            if !found {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(found)
    }

    @Test func aRealExternalSymlinkTargetEditRefreshesTheOpenIndex() async throws {
        let root = try tempRoot(["a.md"])
        let external = try tempRoot(["first.md"])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"), withDestinationURL: external
        )
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        controller.makeWorkspaceEventSource = { try WorkspaceFileEvents(paths: $0) }
        await controller.setFileTreeRoot(root)
        #expect(controller.workspaceEventPaths == [root.path, external.path])
        #expect(controller.currentQuickOpenOrigin != nil)
        #expect(await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath)).contains("linked/first.md"))

        try Data("second".utf8).write(to: external.appendingPathComponent("second.md"))
        var found = false
        for _ in 0 ..< 500 where !found {
            found = await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
                .contains("linked/second.md")
            if !found {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(found)
    }

    @Test func aNewExternalSymlinkBecomesMonitoredAfterTheRootChanges() async throws {
        let root = try tempRoot(["a.md"])
        let external = try tempRoot(["first.md"])
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        controller.makeWorkspaceEventSource = { try WorkspaceFileEvents(paths: $0) }
        await controller.setFileTreeRoot(root)
        #expect(controller.workspaceEventPaths == [root.path])

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"), withDestinationURL: external
        )
        var expanded = false
        for _ in 0 ..< 500 where !expanded {
            expanded = controller.workspaceEventPaths == [root.path, external.path]
            if !expanded {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(expanded)

        try Data("second".utf8).write(to: external.appendingPathComponent("second.md"))
        #expect(await fixture.waitForIndexedPath("linked/second.md"))
    }

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
        controller.makeWorkspaceEventSource = { paths in
            paths.first == second.path ? newEvents : oldEvents
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
        for _ in 0 ..< 200 where controller.workspaceEventSource != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.workspaceEventSource == nil)
        #expect(controller.workspaceEventPaths.isEmpty)
    }
}

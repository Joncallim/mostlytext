import AppKit
import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextSearch
import Themes
import Workspace

/// Existing workspace-index refresh behavior remains intact around the
/// activation freshness optimization.
@MainActor
@Suite("Workspace index refresh behavior")
struct WorkspaceIndexRefreshBehaviorTests {
    private func paths(_ controller: WindowController) async -> Set<String> {
        await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
    }

    func tempRoot(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: root.appendingPathComponent(file))
        }
        return root
    }

    func waitForSearch(
        _ model: FolderSearchModel,
        paths expectedPaths: Set<String>,
        outcome expectedOutcome: FolderSearchOutcome? = nil
    ) async throws {
        for _ in 0 ..< 200 {
            let paths = Set(model.results.map(\.relativePath))
            if !model.isSearching, paths == expectedPaths, model.outcome != nil,
               expectedOutcome == nil || model.outcome == expectedOutcome {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("Folder Search did not reflect the completed index refresh")
    }

    @Test func anActiveFolderSearchFollowsSameRootIndexRefreshes() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle a".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        let search = controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md"])

        try "needle b".write(to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        await controller.refreshWorkspaceIndex()
        try await waitForSearch(search, paths: ["a.md", "b.md"])

        try FileManager.default.removeItem(at: root.appendingPathComponent("a.md"))
        await controller.refreshWorkspaceIndex()
        try await waitForSearch(search, paths: ["b.md"])
    }

    @Test func aFailedIndexRefreshReplacesStaleSearchResultsAndRecoveryRerunsTheQuery() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let probe = IndexWalkProbe(unavailableRoot: root, unavailableWalkNumber: 2)
        let fixture = try await makeController(root: root, index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        let search = controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md"])

        await controller.refreshWorkspaceIndex()
        #expect(probe.injectedUnavailabilityWasObserved)
        try await waitForSearch(search, paths: [], outcome: .indexUnavailable)

        try "needle again".write(to: root.appendingPathComponent("restored.md"), atomically: true, encoding: .utf8)
        await controller.refreshWorkspaceIndex()
        try await waitForSearch(search, paths: ["a.md", "restored.md"])
    }

    @Test func losingTheFolderAccessScopeRetiresVisibleSearchResults() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let events = ManualWorkspaceEvents()
        let fixture = try await makeController(root: root, eventSource: events)
        defer { fixture.retire() }
        let search = fixture.controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md"])

        fixture.controller.fileTreeModel.tearDown()

        #expect(events.wasCancelled)
        #expect(fixture.controller.fileTreeModel.rootAccessURL == nil)
        #expect(search.root == nil)
        #expect(search.results.isEmpty)
        #expect(search.outcome == .indexUnavailable)
        search.query = "another term"
        #expect(search.outcome == .indexUnavailable)
    }

    @Test func automaticRefreshNeverReincludesExcludedOrUnreviewedReplaceTargets() async throws {
        let root = try tempRoot(["a.md", "b.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle a".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "needle b".write(to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        let search = controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md", "b.md"])

        search.isReplaceVisible = true
        search.replacement = "changed"
        search.setIncluded(false, path: "a.md")
        search.requestReplace()
        #expect(search.isConfirmingReplace)
        let previousSummary = FolderReplaceSummary(replacedMatches: 1, replacedFiles: 1, skipped: [])
        search.replaceSummary = previousSummary

        try "needle c".write(to: root.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
        await controller.refreshWorkspaceIndex()
        try await waitForSearch(search, paths: ["a.md", "b.md", "c.md"])

        #expect(!search.isConfirmingReplace)
        #expect(search.replaceSummary == previousSummary)
        #expect(Set(search.includedResults.map(\.relativePath)) == ["b.md"])
        #expect(!search.isIncluded(path: "a.md"))
        #expect(!search.isIncluded(path: "c.md"))

        search.requestReplace()
        search.confirmReplace()
        for _ in 0 ..< 200 where search.isReplacing {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(search.replaceSummary?.replacedFiles == 1)
        #expect(try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8) == "needle a")
        #expect(try String(contentsOf: root.appendingPathComponent("b.md"), encoding: .utf8) == "changed b")
        #expect(try String(contentsOf: root.appendingPathComponent("c.md"), encoding: .utf8) == "needle c")
    }

    @Test func changedResultRevisionNeedsFreshReplaceSelectionAfterIndexRefresh() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        let search = controller.folderSearchModel
        search.query = "needle"
        try await waitForSearch(search, paths: ["a.md"])
        search.isReplaceVisible = true
        #expect(search.isIncluded(path: "a.md"))

        try "needle changed externally".write(
            to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8
        )
        await controller.refreshWorkspaceIndex()
        try await waitForSearch(search, paths: ["a.md"])

        #expect(!search.isIncluded(path: "a.md"))
        #expect(!search.canReplace)
    }

    @Test func aFileAddedByAnotherProgramAppearsAfterTheIndexRefreshes() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        #expect(await paths(controller) == ["a.md"])

        try Data().write(to: root.appendingPathComponent("added-externally.md"))
        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller) == ["a.md", "added-externally.md"])
    }

    @Test func aDeletedFileDisappearsAfterTheIndexRefreshes() async throws {
        let root = try tempRoot(["a.md", "b.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller

        try FileManager.default.removeItem(at: root.appendingPathComponent("b.md"))
        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller) == ["a.md"])
    }

    @Test func theAppsOwnFileOperationsRefreshTheIndexWithoutAnExplicitCall() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller

        let created = try await controller.fileTreeModel.createFile(in: root.standardizedFileURL)

        var found = false
        for _ in 0 ..< 200 where !found {
            found = await paths(controller).contains(created.url.lastPathComponent)
            if !found {
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        #expect(found)
    }

    @Test func refreshWithoutAnOpenFolderIsANoOp() async throws {
        let root = try tempRoot([])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(nil)

        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller).isEmpty)
    }

    @Test func aRefreshWithinTheMinimumIntervalIsSkipped() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.refreshWorkspaceIndex()
        try Data().write(to: root.appendingPathComponent("late.md"))

        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(await paths(controller) == ["a.md"])
    }

    @Test func successfulInitialBuildMakesActivationRefreshSkipTheDuplicateWalk() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IndexWalkProbe()
        let fixture = try await makeController(root: root, index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 1)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(await paths(controller) == ["a.md"])
    }

    @Test func failedForcedRefreshInvalidatesFreshnessSoActivationRetries() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IndexWalkProbe(unavailableRoot: root, unavailableWalkNumber: 2)
        let fixture = try await makeController(root: root, index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        #expect(probe.count == 1)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(await paths(controller) == ["a.md"])

        await controller.refreshWorkspaceIndex()

        guard case .failed = await controller.workspaceFileIndex.state else {
            Issue.record("the forced refresh should fail after access is removed")
            return
        }
        #expect(probe.injectedUnavailabilityWasObserved)
        #expect(controller.lastWorkspaceIndexRefresh == nil)
        #expect(controller.lastWorkspaceIndexRefreshRoot == nil)
        #expect(controller.lastWorkspaceIndexRefreshGeneration == nil)

        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 3)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(controller.lastWorkspaceIndexRefreshRoot == root.standardizedFileURL)
        guard case .ready = await controller.workspaceFileIndex.state else {
            Issue.record("activation should rebuild the restored root despite the prior throttle")
            return
        }
        #expect(await paths(controller) == ["a.md"])
    }
}

extension WorkspaceIndexRefreshBehaviorTests {
    func makeController(
        root: URL,
        index: WorkspaceFileIndex = WorkspaceFileIndex(),
        eventSource: ManualWorkspaceEvents? = nil
    ) async throws -> ControllerFixture {
        let suiteName = "index-refresh-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: stateDirectory.appendingPathComponent("session.json")),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        model.newDocument()
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            workspaceFileIndex: index
        )
        controller.makeWorkspaceEventSource = { _ in eventSource ?? ManualWorkspaceEvents() }
        coordinator.controllers = [controller]
        await controller.setFileTreeRoot(root)
        return ControllerFixture(
            controller: controller,
            coordinator: coordinator,
            defaults: defaults,
            suiteName: suiteName,
            stateDirectory: stateDirectory
        )
    }
}

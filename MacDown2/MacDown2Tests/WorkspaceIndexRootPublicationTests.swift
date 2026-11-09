import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextSearch
import Themes
import Workspace

@MainActor
@Suite("Workspace index root publication")
struct WorkspaceIndexRootPublicationTests {
    private func controllerFixture(index: WorkspaceFileIndex) throws -> ControllerFixture {
        let suiteName = "index-publication-\(UUID().uuidString)"
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
        coordinator.controllers = [controller]
        return ControllerFixture(
            controller: controller,
            coordinator: coordinator,
            defaults: defaults,
            suiteName: suiteName,
            stateDirectory: stateDirectory
        )
    }

    private func tempRoot(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: root.appendingPathComponent(file))
        }
        return root
    }

    private func paths(_ controller: WindowController) async -> Set<String> {
        await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
    }

    @Test func quickOpenOriginWaitsForTheNewRootIndexPublication() async throws {
        let rootA = try tempRoot(["same.md"])
        let rootB = try tempRoot(["same.md"])
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let gate = IndexWalkGate()
        let probe = IndexWalkProbe(heldRoot: rootB, gate: gate)
        let fixture = try controllerFixture(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        await controller.setFileTreeRoot(rootA)
        let oldOrigin = try #require(controller.currentQuickOpenOrigin)
        #expect(oldOrigin.lexicalRoot == rootA.standardizedFileURL)

        let beforeTree = FolderSearchGate()
        controller.beforeRootRebuild = { await beforeTree.wait() }
        defer { controller.beforeRootRebuild = nil }
        let change = Task { await controller.setFileTreeRoot(rootB) }
        guard await FolderSearchGate.waitForEntry(beforeTree.entered) else {
            beforeTree.release()
            gate.release()
            await change.value
            Issue.record("root switch did not pause before replacing the tree")
            return
        }
        #expect(controller.fileTreeModel.rootAccessURL == rootA.standardizedFileURL)
        #expect(controller.currentQuickOpenOrigin == nil)
        beforeTree.release()
        guard await gate.waitUntilBlocked() else {
            gate.release()
            await change.value
            Issue.record("new-root index walk did not pause")
            return
        }

        // The tree already points at B while the index still retains A's
        // published row. Opening a panel in this interval must not pair that
        // row with B's root, even if B has a file of the same name.
        #expect(controller.fileTreeModel.rootAccessURL == rootB.standardizedFileURL)
        let stale = await controller.workspaceFileIndex.querySnapshot("same", limit: 10)
        #expect(stale.paths.map(\.relativePath) == ["same.md"])
        #expect(controller.currentQuickOpenOrigin == nil)

        gate.release()
        await change.value
        let newOrigin = try #require(controller.currentQuickOpenOrigin)
        #expect(newOrigin.lexicalRoot == rootB.standardizedFileURL)
        #expect(newOrigin.generation != oldOrigin.generation)
    }

    @Test func changingRootRetiresOldSearchRowsBeforeRebuildAwaits() async throws {
        let rootA = try tempRoot(["a.md"])
        let rootB = try tempRoot(["b.md"])
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let fixture = try controllerFixture(index: WorkspaceFileIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(rootA)
        let accessRoot = try #require(controller.folderSearchModel.root)
        let origin = FolderSearchOrigin(
            controller: controller,
            generation: controller.workspaceRootRequestGeneration,
            lexicalRoot: rootA.standardizedFileURL,
            accessRoot: accessRoot
        )
        #expect(origin.isCurrent)

        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer { controller.beforeRootRebuild = nil }
        let change = Task { await controller.setFileTreeRoot(rootB) }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await change.value
            Issue.record("root change did not pause before rebuilding")
            return
        }

        #expect(controller.folderSearchModel.root == nil)
        #expect(!origin.isCurrent)
        await fixture.coordinator.openFolderSearchResult(
            relativePath: "a.md", root: rootA.standardizedFileURL,
            folderAccessURL: accessRoot, range: NSRange(location: 0, length: 1), origin: origin
        )
        #expect(fixture.coordinator.controllers.count == 1)

        gate.release()
        await change.value
        #expect(controller.folderSearchModel.root == rootB.standardizedFileURL)
    }

    @Test func changingRootDuringResultLoadCannotPublishOldFolderDocument() async throws {
        let rootA = try tempRoot(["result.md"])
        let rootB = try tempRoot(["other.md"])
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let fixture = try controllerFixture(index: WorkspaceFileIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(rootA)
        let accessRoot = try #require(controller.folderSearchModel.root)
        let origin = FolderSearchOrigin(
            controller: controller,
            generation: controller.workspaceRootRequestGeneration,
            lexicalRoot: rootA.standardizedFileURL,
            accessRoot: accessRoot
        )
        let gate = FolderSearchGate()
        fixture.coordinator.afterFolderSearchFileLoad = { await gate.wait() }
        let opening = Task {
            await fixture.coordinator.openFolderSearchResult(
                relativePath: "result.md", root: rootA.standardizedFileURL,
                folderAccessURL: accessRoot, range: NSRange(location: 0, length: 1), origin: origin
            )
        }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await opening.value
            Issue.record("folder-result open did not pause after loading")
            return
        }

        await controller.setFileTreeRoot(rootB)
        gate.release()
        await opening.value
        #expect(fixture.coordinator.controllers.count == 1)
        #expect(fixture.coordinator.controllerForDocument(url: rootA.appendingPathComponent("result.md")) == nil)
    }
}

extension WorkspaceIndexRootPublicationTests {
    @Test func changingQueryDuringResultLoadCannotPublishOldSearchRow() async throws {
        let root = try tempRoot(["result.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try "needle".write(to: root.appendingPathComponent("result.md"), atomically: true, encoding: .utf8)
        let fixture = try controllerFixture(index: WorkspaceFileIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(root)
        controller.folderSearchModel.query = "needle"
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while controller.folderSearchModel.presentedResults.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let row = try #require(controller.folderSearchModel.presentedResults.first)
        let accessRoot = try #require(controller.folderSearchModel.root)
        let origin = FolderSearchOrigin(
            controller: controller,
            generation: controller.workspaceRootRequestGeneration,
            lexicalRoot: root.standardizedFileURL,
            accessRoot: accessRoot,
            presentedResult: row
        )
        #expect(origin.isCurrent)

        let gate = FolderSearchGate()
        fixture.coordinator.afterFolderSearchFileLoad = { await gate.wait() }
        let opening = Task {
            await fixture.coordinator.openFolderSearchResult(
                relativePath: "result.md", root: root.standardizedFileURL,
                folderAccessURL: accessRoot, range: NSRange(location: 0, length: 6), origin: origin
            )
        }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await opening.value
            Issue.record("folder-result open did not pause after loading")
            return
        }
        controller.folderSearchModel.query = "other"
        #expect(!origin.isCurrent)
        gate.release()
        await opening.value
        #expect(fixture.coordinator.controllers.count == 1)
        #expect(fixture.coordinator.controllerForDocument(url: root.appendingPathComponent("result.md")) == nil)
    }
}

extension WorkspaceIndexRootPublicationTests {
    @Test func replacingAccessForSameLexicalRootRetiresOldResultsImmediately() async throws {
        let lexicalRoot = try tempRoot(["same.md"])
        let newAccess = try tempRoot(["same.md"])
        defer {
            try? FileManager.default.removeItem(at: lexicalRoot)
            try? FileManager.default.removeItem(at: newAccess)
        }
        let fixture = try controllerFixture(index: WorkspaceFileIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(lexicalRoot)
        let oldAccess = try #require(controller.folderSearchModel.root)
        let oldOrigin = FolderSearchOrigin(
            controller: controller,
            generation: controller.workspaceRootRequestGeneration,
            lexicalRoot: lexicalRoot.standardizedFileURL,
            accessRoot: oldAccess
        )
        #expect(oldOrigin.isCurrent)

        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer { controller.beforeRootRebuild = nil }
        let change = Task { await controller.setFileTreeRoot(lexicalRoot, accessURL: newAccess) }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await change.value
            Issue.record("same-path access replacement did not pause before rebuilding")
            return
        }

        #expect(controller.folderSearchModel.root == nil)
        #expect(!oldOrigin.isCurrent)
        gate.release()
        await change.value
        #expect(controller.folderSearchModel.root == newAccess.standardizedFileURL)
    }

    @Test func activationRefreshDuringRootChangeDoesNotUseThePreviousRoot() async throws {
        let rootA = try tempRoot(["a.md"])
        let rootB = try tempRoot(["b.md"])
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let probe = IndexWalkProbe()
        let fixture = try controllerFixture(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(rootA)

        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer { controller.beforeRootRebuild = nil }
        let changingRoot = Task { await controller.setFileTreeRoot(rootB) }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await changingRoot.value
            Issue.record("the root change did not pause before replacing the file-tree root")
            return
        }

        // A closed search scope makes an accidental publication of the still-
        // current file-tree root observable while the new root request waits.
        controller.folderSearchModel.setRoot(nil)
        await controller.refreshWorkspaceIndex(minInterval: 60)
        #expect(controller.fileTreeModel.rootAccessURL == rootA.standardizedFileURL)
        #expect(controller.folderSearchModel.root == nil)
        #expect(controller.lastWorkspaceIndexRefreshRoot == nil)
        #expect(probe.count == 1)

        gate.release()
        await changingRoot.value

        #expect(controller.fileTreeModel.rootAccessURL == rootB.standardizedFileURL)
        #expect(controller.folderSearchModel.root == rootB.standardizedFileURL)
        #expect(controller.lastWorkspaceIndexRefreshRoot == rootB.standardizedFileURL)
        #expect(probe.count == 2)
        #expect(await paths(controller) == ["b.md"])
    }

    @Test func activationRefreshUsesRootAfterAcceptedFolderRemap() async throws {
        let rootA = try tempRoot(["b.md"])
        let rootB = rootA.deletingLastPathComponent()
            .appendingPathComponent("remapped-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let probe = IndexWalkProbe()
        let fixture = try controllerFixture(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(rootA)
        #expect(probe.count == 1)

        let accessRoot = try #require(controller.folderSearchModel.root)
        let oldOrigin = FolderSearchOrigin(
            controller: controller,
            generation: controller.workspaceRootRequestGeneration,
            lexicalRoot: rootA.standardizedFileURL,
            accessRoot: accessRoot
        )
        #expect(oldOrigin.isCurrent)

        try FileManager.default.moveItem(at: rootA, to: rootB)
        fixture.coordinator.remapFolderRootsAfterAcceptedMove(from: rootA, to: rootB)
        #expect(controller.fileTreeModel.rootAccessURL == rootB.standardizedFileURL)
        #expect(!oldOrigin.isCurrent)

        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 2)
        #expect(controller.lastWorkspaceIndexRefreshRoot == rootB.standardizedFileURL)
        #expect(await paths(controller) == ["b.md"])
    }
}

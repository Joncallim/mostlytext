import AppKit
import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
@testable import TextSearch
import Themes
import Workspace

/// #183 F18 — Quick Open / Folder Search follow changes after the folder was
/// opened: external edits (refresh on window activation) and this app's own
/// file operations.
@MainActor
@Suite("Workspace index freshness (#183 F18)")
struct WorkspaceIndexFreshnessTests {
    private func makeUnrootedController(index: WorkspaceFileIndex) throws -> ControllerFixture {
        let suiteName = "index-freshness-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let sessionURL = stateDirectory.appendingPathComponent("session.json")
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: sessionURL),
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

    private func paths(_ controller: WindowController) async -> Set<String> {
        await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
    }

    private func waitForWalk(_ gate: IndexWalkGate) async -> Bool {
        await gate.waitUntilBlocked()
    }

    private func tempRoot(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: root.appendingPathComponent(file))
        }
        return root
    }

    @Test func sameRootActivationSupersessionPublishesSearchOnlyAfterTheCurrentBuildIsReady() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let initialGate = IndexWalkGate()
        let activationGate = IndexWalkGate()
        let probe = IndexWalkProbe(
            heldRoot: root,
            gatesByWalk: [1: initialGate, 2: activationGate]
        )
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        let initial = Task { await controller.setFileTreeRoot(root) }
        guard await waitForWalk(initialGate) else {
            initialGate.release()
            await initial.value
            Issue.record("the initial root walk did not start")
            return
        }
        let activation = Task { await controller.refreshWorkspaceIndex(minInterval: 60) }
        guard await waitForWalk(activationGate) else {
            initialGate.release()
            activationGate.release()
            await initial.value
            await activation.value
            Issue.record("the activation walk did not supersede the initial walk")
            return
        }

        initialGate.release()
        await initial.value
        #expect(controller.folderSearchModel.root == nil)
        #expect(controller.lastWorkspaceIndexRefresh == nil)

        activationGate.release()
        await activation.value

        #expect(controller.folderSearchModel.root == root.standardizedFileURL)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(probe.count == 2)
        #expect(await paths(controller) == ["a.md"])
    }

    @Test func olderInitialCompletionCannotReplaceNewerSameRootFreshness() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = IndexWalkGate()
        let probe = IndexWalkProbe(heldRoot: root, gate: gate)
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        let initial = Task { await controller.setFileTreeRoot(root) }
        guard await waitForWalk(gate) else {
            gate.release()
            await initial.value
            Issue.record("the initial root walk did not start")
            return
        }
        await controller.refreshWorkspaceIndex(minInterval: 60)
        let newestFreshness = controller.lastWorkspaceIndexRefresh
        let newestBuild = controller.workspaceIndexBuildGeneration
        #expect(newestFreshness != nil)
        #expect(controller.folderSearchModel.root == root.standardizedFileURL)

        gate.release()
        await initial.value

        #expect(controller.workspaceIndexBuildGeneration == newestBuild)
        #expect(controller.lastWorkspaceIndexRefresh == newestFreshness)
        #expect(controller.folderSearchModel.root == root.standardizedFileURL)
        #expect(probe.count == 2)
    }

    @Test func forcedRefreshAndExplicitMutationStillWalkAgain() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IndexWalkProbe()
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        await fixture.controller.setFileTreeRoot(root)
        #expect(probe.count == 1)

        await fixture.controller.refreshWorkspaceIndex()
        #expect(probe.count == 2)

        let created = try await fixture.controller.fileTreeModel.createFile(in: root.standardizedFileURL)
        for _ in 0 ..< 200 where probe.completedCount < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let published = await fixture.waitForIndexedPath(created.url.lastPathComponent)
        #expect(probe.count == 3)
        #expect(probe.completedCount == 3)
        #expect(published)
    }

    @Test func delayedOldACompletionCannotReplaceFreshnessAfterAtoBtoA() async throws {
        let rootA = try tempRoot(["a.md"])
        let rootB = try tempRoot(["b.md"])
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let gate = IndexWalkGate()
        let probe = IndexWalkProbe(heldRoot: rootA, gate: gate)
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        let firstA = Task { await controller.setFileTreeRoot(rootA) }
        guard await waitForWalk(gate) else {
            gate.release()
            await firstA.value
            Issue.record("the first A walk did not start")
            return
        }
        await controller.setFileTreeRoot(rootB)
        let rootBGenerationValue = controller.lastWorkspaceIndexRefreshGeneration
        await controller.setFileTreeRoot(rootA)
        let latestAFreshnessValue = controller.lastWorkspaceIndexRefresh
        let latestAGenerationValue = controller.lastWorkspaceIndexRefreshGeneration
        gate.release()
        await firstA.value

        let rootBGeneration = try #require(rootBGenerationValue)
        let latestAFreshness = try #require(latestAFreshnessValue)
        let latestAGeneration = try #require(latestAGenerationValue)

        #expect(probe.count == 3)
        #expect(controller.fileTreeModel.rootAccessURL == rootA.standardizedFileURL)
        #expect(controller.folderSearchModel.root == rootA.standardizedFileURL)
        #expect(await paths(controller) == ["a.md"])
        #expect(controller.lastWorkspaceIndexRefresh == latestAFreshness)
        #expect(latestAGeneration != rootBGeneration)
        #expect(controller.lastWorkspaceIndexRefreshGeneration == latestAGeneration)
        await controller.refreshWorkspaceIndex(minInterval: 60)
        #expect(probe.count == 3)
    }

    @Test func clearingOrClosingWhileAnInitialWalkIsHeldDoesNotPublishOrBecomeFresh() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = IndexWalkGate()
        let probe = IndexWalkProbe(heldRoot: root, gate: gate)
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        let initial = Task { await controller.setFileTreeRoot(root) }
        guard await waitForWalk(gate) else {
            gate.release()
            await initial.value
            Issue.record("the initial walk did not start")
            return
        }
        await controller.setFileTreeRoot(nil)
        gate.release()
        await initial.value

        #expect(controller.lastWorkspaceIndexRefresh == nil)
        #expect(controller.lastWorkspaceIndexRefreshGeneration == nil)
        #expect(controller.folderSearchModel.root == nil)
        #expect(await paths(controller).isEmpty)

        let secondGate = IndexWalkGate()
        let closedProbe = IndexWalkProbe(heldRoot: root, gate: secondGate)
        let closedFixture = try makeUnrootedController(index: closedProbe.makeIndex())
        defer { closedFixture.retire() }
        let closedController = closedFixture.controller
        let closing = Task { await closedController.setFileTreeRoot(root) }
        guard await waitForWalk(secondGate) else {
            secondGate.release()
            await closing.value
            Issue.record("the closing walk did not start")
            return
        }
        closedFixture.coordinator.removeController(closedController)
        closedController.close()
        secondGate.release()
        await closing.value

        #expect(closedController.isClosed)
        #expect(closedController.lastWorkspaceIndexRefresh == nil)
        #expect(closedController.folderSearchModel.root == nil)
    }

    @Test func failedInitialBuildDoesNotEarnFreshness() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IndexWalkProbe(unavailableRoot: root, unavailableWalkNumber: 1)
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        await controller.setFileTreeRoot(root)

        guard case .failed = await controller.workspaceFileIndex.state else {
            Issue.record("an unreadable root must leave the index failed")
            return
        }
        #expect(probe.injectedUnavailabilityWasObserved)
        #expect(controller.fileTreeModel.rootAccessURL == root.standardizedFileURL)
        #expect(controller.lastWorkspaceIndexRefresh == nil)
        #expect(controller.lastWorkspaceIndexRefreshGeneration == nil)
        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 2)
        if case .ready = await controller.workspaceFileIndex.state {
            #expect(controller.lastWorkspaceIndexRefresh != nil)
        } else {
            Issue.record("the restored root should build a ready index on activation")
        }
    }
}

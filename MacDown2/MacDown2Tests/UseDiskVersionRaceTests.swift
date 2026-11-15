import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// #183 F01 (tenth review R10-01): the Use-Disk-Version / Reopen-with-Encoding reload captured a disk snapshot, awaited
/// the recovery cleanup, then unconditionally installed it over the active document. An edit, tab switch or Save As
/// during that actor hop was overwritten; and Reopen reported success from the document's revision alone.
@MainActor
struct UseDiskVersionRaceTests {
    @Test func recoveryVersionReassertionNeverLowersAnAlreadyNewerDraft() {
        let current = FileDocument(text: "draft").updatingText("new draft")
        let unchanged = current.advancingRecoveryVersion(after: 0)
        let raised = current.advancingRecoveryVersion(after: current.mutationGeneration)
        #expect(unchanged.mutationGeneration == current.mutationGeneration)
        #expect(raised.mutationGeneration > current.mutationGeneration)
        #expect(raised.text == current.text)
        #expect(raised.state == current.state)
    }

    private struct Fixture {
        let controller: WindowController
        let coordinator: WindowCoordinator
        let model: WorkspaceModel
        let directory: URL
    }

    private func makeFixture(
        bytes: Data, recoveryExecutor: any RecoveryActionExecuting = DefaultRecoveryActionExecutor()
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("doc.txt")
        try bytes.write(to: url)
        let defaults = try #require(UserDefaults(suiteName: "reopen-encoding-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        try model.tabStore.newTab(document: FileDocument(fileURL: url, recoveryBuffer: recovery).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recoveryExecutor: recoveryExecutor
        )
        coordinator.controllers = [controller]
        return Fixture(controller: controller, coordinator: coordinator, model: model, directory: directory)
    }

    @Test func anEditDuringTheRecoveryCleanupIsNotOverwrittenByTheReload() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        fixture.controller.externalFileController.afterUseExternalRecoveryCleanup = {
            model.tabStore.updateActiveDocument { $0.updatingText("typed while the cleanup was suspended") }
        }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .superseded)
        #expect(model.activeDocument?.text == "typed while the cleanup was suspended")
        #expect(model.activeDocument?.state == .dirty)
        #expect(model.activeDocument?.encoding.encoding == .utf8)
        await fixture.controller.externalFileController.drainRecovery()
        let current = try #require(model.activeDocument)
        #expect(try await current.recoveryBuffer.load(for: current.id, epoch: current.recoveryEpoch)
            == "typed while the cleanup was suspended")
    }

    @Test func aReloadThatIsNotSupersededStillLandsAndIsReportedAsReopened() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .reopened)
        #expect(fixture.model.activeDocument?.encoding.encoding == .isoLatin1)
    }

    /// #17 F01 / #12: a second disk edit can advance the pending conflict
    /// revision without changing the local text, document lifetime or state.
    @Test func aNewerExternalRevisionDuringCleanupSupersedesUseDiskVersion() async throws {
        let fixture = try makeFixture(bytes: Data("original disk".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let controller = fixture.controller.externalFileController
        let document = try #require(model.activeDocument)
        let fileURL = try #require(document.fileURL)
        model.tabStore.updateActiveDocument { $0.updatingText("local draft") }
        try Data("first external".utf8).write(to: fileURL, options: .atomic)
        let first = try document.fileStore.readSnapshot(from: fileURL)
        let conflicted = try #require(model.activeDocument).reconcilingExternalSnapshot(first).document
        model.tabStore.updateActiveDocument { _ in conflicted }
        #expect(conflicted.state == .conflict)
        #expect(await conflicted.persistRecovery())

        var newest: FileSnapshot?
        controller.afterUseExternalRecoveryCleanup = {
            do {
                try Data("newer external".utf8).write(to: fileURL, options: .atomic)
                let snapshot = try document.fileStore.readSnapshot(from: fileURL)
                let current = try #require(model.activeDocument)
                let updated = current.reconcilingExternalSnapshot(snapshot)
                #expect(updated.disposition == .conflictUpdated)
                model.tabStore.updateActiveDocument { _ in updated.document }
                newest = snapshot
            } catch {
                Issue.record("Could not advance the external conflict during cleanup: \(error)")
            }
        }

        let result = await controller.applyConflictResolution(
            .useExternal, snapshot: first, document: conflicted, model: model
        )

        let second = try #require(newest)
        let current = try #require(model.activeDocument)
        #expect(result == .superseded)
        #expect(current.text == "local draft")
        #expect(current.state == .conflict)
        #expect(current.pendingExternalRevision == second.revision)
        #expect(try Data(contentsOf: fileURL) == Data("newer external".utf8))
        await controller.drainRecovery()
        #expect(try await current.recoveryBuffer.load(for: current.id, epoch: current.recoveryEpoch) == "local draft")
    }

    @Test func newerRecoveryRecordBlocksAnOlderUseDiskCleanup() async throws {
        let fixture = try makeFixture(bytes: Data("original disk".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let controller = fixture.controller.externalFileController
        let document = try #require(model.activeDocument)
        let fileURL = try #require(document.fileURL)
        model.tabStore.updateActiveDocument { $0.updatingText("local draft") }
        try Data("external disk".utf8).write(to: fileURL, options: .atomic)
        let snapshot = try document.fileStore.readSnapshot(from: fileURL)
        let conflicted = try #require(model.activeDocument).reconcilingExternalSnapshot(snapshot).document
        model.tabStore.updateActiveDocument { _ in conflicted }
        #expect(await conflicted.persistRecovery())
        #expect(try await conflicted.recoveryBuffer.saveCurrentLifetime(
            content: conflicted.text, for: conflicted.id,
            version: conflicted.mutationGeneration + 2, epoch: conflicted.recoveryEpoch
        ))

        let result = await controller.applyConflictResolution(
            .useExternal, snapshot: snapshot, document: conflicted, model: model
        )

        #expect(result == .cleanupBlocked)
        #expect(model.activeDocument?.text == "local draft")
        #expect(model.activeDocument?.state == .conflict)
        #expect(try await conflicted.recoveryBuffer.load(for: conflicted.id, epoch: conflicted.recoveryEpoch)
            == "local draft")
    }

    @Test func switchingTabsDuringConflictCleanupKeepsTheInactiveDraftRecoverable() async throws {
        let fixture = try makeFixture(bytes: Data("original disk".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let controller = fixture.controller.externalFileController
        let document = try #require(model.activeDocument)
        let tabID = try #require(model.tabStore.activeTab?.id)
        let fileURL = try #require(document.fileURL)
        model.tabStore.updateActiveDocument { $0.updatingText("inactive draft") }
        try Data("external disk".utf8).write(to: fileURL, options: .atomic)
        let snapshot = try document.fileStore.readSnapshot(from: fileURL)
        let conflicted = try #require(model.activeDocument).reconcilingExternalSnapshot(snapshot).document
        model.tabStore.updateActiveDocument { _ in conflicted }
        #expect(await conflicted.persistRecovery())
        controller.afterUseExternalRecoveryCleanup = {
            model.tabStore.newTab(document: FileDocument(text: "new active tab"))
        }

        let result = await controller.applyConflictResolution(
            .useExternal, snapshot: snapshot, document: conflicted, model: model
        )

        await controller.drainRecovery()
        let inactive = try #require(model.tabStore.tabs.first(where: { $0.id == tabID })?.document)
        #expect(result == .superseded)
        #expect(model.activeDocument?.text == "new active tab")
        #expect(inactive.text == "inactive draft")
        #expect(inactive.state == .conflict)
        #expect(try await inactive.recoveryBuffer.load(for: inactive.id, epoch: inactive.recoveryEpoch)
            == "inactive draft")
    }

    @Test func failedInactiveDraftPersistenceOffersRetryAfterConflictCleanup() async throws {
        let executor = ScriptedRecoveryExecutor()
        let fixture = try makeFixture(bytes: Data("original disk".utf8), recoveryExecutor: executor)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let controller = fixture.controller.externalFileController
        let document = try #require(model.activeDocument)
        let tabID = try #require(model.tabStore.activeTab?.id)
        let fileURL = try #require(document.fileURL)
        model.tabStore.updateActiveDocument { $0.updatingText("inactive draft") }
        try Data("external disk".utf8).write(to: fileURL, options: .atomic)
        let snapshot = try document.fileStore.readSnapshot(from: fileURL)
        let conflicted = try #require(model.activeDocument).reconcilingExternalSnapshot(snapshot).document
        model.tabStore.updateActiveDocument { _ in conflicted }
        #expect(await conflicted.persistRecovery())
        controller.afterUseExternalRecoveryCleanup = {
            model.tabStore.newTab(document: FileDocument(text: "new active tab"))
        }
        await executor.failNext(.persist)

        let result = await controller.applyConflictResolution(
            .useExternal, snapshot: snapshot, document: conflicted, model: model
        )

        await controller.drainRecovery()
        #expect(result == .superseded)
        #expect(controller.recoveryRetryKind == .persist)
        controller.retryRecoveryCleanup()
        await controller.drainRecovery()
        let inactive = try #require(model.tabStore.tabs.first(where: { $0.id == tabID })?.document)
        #expect(controller.recoveryRetryKind == nil)
        #expect(try await inactive.recoveryBuffer.load(for: inactive.id, epoch: inactive.recoveryEpoch)
            == "inactive draft")
    }

    // Handoff regression 1 (#375): the other transitions during the held cleanup.

    @Test func aTabSwitchDuringTheRecoveryCleanupLeavesBothDocumentsAlone() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let originalID = try #require(model.activeDocument?.id)
        let original = try #require(model.activeDocument)
        fixture.controller.externalFileController.afterUseExternalRecoveryCleanup = {
            model.tabStore.newTab(document: FileDocument(text: "other tab text"))
        }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .superseded)
        #expect(model.activeDocument?.text == "other tab text", "the newly active tab must not receive the snapshot")
        #expect(model.activeDocument?.encoding.encoding == .utf8)
        let untouched = model.tabStore.tabs.compactMap(\.document).first { $0.id == originalID }
        #expect(untouched?.text == original.text, "the original tab keeps its text")
        #expect(untouched?.encoding.encoding == .utf8, "and its encoding")
    }

    @Test func aRecoveryLifetimeChangeDuringTheCleanupSupersedesTheReload() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let epochBefore = try #require(model.activeDocument?.recoveryEpoch)
        fixture.controller.externalFileController.afterUseExternalRecoveryCleanup = {
            model.tabStore.updateActiveDocument { $0.withFreshRecoveryLifetime() }
        }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .superseded)
        #expect(model.activeDocument?.recoveryEpoch != epochBefore, "the new lifetime is kept, not overwritten")
        #expect(model.activeDocument?.encoding.encoding == .utf8)
    }

    @Test func disposalDuringTheRecoveryCleanupNeverInstallsTheSnapshot() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let controller = fixture.controller.externalFileController
        let textBefore = try #require(model.activeDocument?.text)
        controller.afterUseExternalRecoveryCleanup = {
            controller.dispose()
        }

        let result = await controller.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result != .reopened)
        #expect(model.activeDocument?.text == textBefore)
        #expect(model.activeDocument?.encoding.encoding == .utf8)
    }
}

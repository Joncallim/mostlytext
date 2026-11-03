import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// "Close Without Saving" on the deleted-file alert closed the window but left the discarded text in
/// the recovery store, where a stale session replay could bring it back as a dirty tab.
@MainActor
struct DeletedDocumentDiscardTests {
    @Test func discardingADeletedDocumentRetiresItsRecoveryAndClosesTheWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("gone.md")
        try "on disk".write(to: file, atomically: true, encoding: .utf8)
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let defaults = try #require(UserDefaults(suiteName: "discard-deleted-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            recoveryBuffer: buffer,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        let dirty = try FileDocument(fileURL: file, recoveryBuffer: buffer).load().updatingText("unsaved words")
        #expect(await dirty.persistRecovery())
        model.tabStore.newTab(document: dirty)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        #expect((controller.window as? DocumentWindow)?.documentRepresentedURL == file)
        #expect(try await buffer.load(for: dirty.id, epoch: dirty.recoveryEpoch) == "unsaved words")

        await coordinator.discardDeletedDocument(in: controller)

        #expect(coordinator.controllers.isEmpty)
        #expect(try await buffer.load(for: dirty.id, epoch: dirty.recoveryEpoch) == nil)
    }
}

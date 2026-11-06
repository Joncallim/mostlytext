import AppKit
import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Preview
import Testing
import Themes
import Workspace

/// Actual document-window wiring with only disposable files and preferences.
@MainActor
final class PreviewProductionFixture {
    let folder: URL
    let coordinator: WindowCoordinator
    let first: WindowController
    let copyHarness = SecuredMarkdownMountedTests()
    private let defaults: UserDefaults
    private let suite: String
    private let preferences: FileTreePreferences

    init(source: String, name: String = "source.md") throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        suite = "preview-production-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        self.defaults = defaults
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        self.preferences = preferences
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: folder.appendingPathComponent("session.json")),
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        self.coordinator = coordinator
        first = try Self.makeController(name, source, folder, coordinator, preferences)
        coordinator.controllers = [first]
        first.showWindow(nil)
        coordinator.updateKeyModel()
        do {
            try copyHarness.smallPNG().write(to: folder.appendingPathComponent("image.png"))
        } catch {
            dispose()
            throw error
        }
    }

    func addDocument(_ name: String, source: String) throws -> WindowController {
        let controller = try Self.makeController(name, source, folder, coordinator, preferences)
        coordinator.controllers.append(controller)
        controller.showWindow(nil)
        coordinator.updateKeyModel()
        return controller
    }

    func dispose() {
        for controller in coordinator.controllers {
            coordinator.removeController(controller)
            controller.close()
        }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    func root(_ controller: WindowController? = nil) throws -> NSView {
        try #require((controller ?? first).window?.contentView)
    }

    func selection(for controller: WindowController? = nil) throws -> PreviewResourceFolderSelection {
        let url = try #require((controller ?? first).model.activeDocument?.fileURL)
        return try #require(PreviewResourceFolderSelection.fixture(documentURL: url, folderURL: folder))
    }

    func installGrant(on controller: WindowController? = nil) async throws {
        let controller = controller ?? first
        let document = try #require(controller.model.activeDocument)
        let owner = controller.previewResourceState
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection(for: controller), from: origin) { controller.model.activeDocument }
    }

    func wait(_ message: String, until ready: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            first.window?.contentView?.layoutSubtreeIfNeeded()
            first.window?.displayIfNeeded()
            if ready() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("\(message)")
        throw PreviewResourceAdmissionError.limitExceeded
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func makeController(
        _ name: String, _ source: String, _ folder: URL,
        _ coordinator: WindowCoordinator, _ preferences: FileTreePreferences
    ) throws -> WindowController {
        let url = folder.appendingPathComponent(name)
        try Data(source.utf8).write(to: url)
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(fileURL: url, text: source))
        let tab = try #require(model.tabStore.activeTabID)
        model.tabStore.setPreviewLayout(.previewOnly, for: tab)
        return WindowController(
            model: model, coordinator: coordinator, themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry, fileTreePreferences: preferences
        )
    }
}

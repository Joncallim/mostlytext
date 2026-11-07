import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
struct DocumentWindowSettingsTests {
    @Test func distinctDocumentRootsReceiveInitialAndLiveSharedSettings() async throws {
        let domain = "document-window-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        var store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.editor = EditorSettings(font: FontDescriptor(familyName: "Missing Fixture Font", size: 23),
                                      indentationWidth: 2)
        let settings = AppSettingsModel(store: store)
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = WindowCoordinator(
            sessionStore: NoOpSessionStore(), recoveryBuffer: recovery,
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: settings, workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        defer {
            for controller in coordinator.controllers {
                coordinator.removeController(controller)
                controller.close()
            }
        }

        let first = try makeWindow(coordinator: coordinator, recovery: recovery)
        let second = try makeWindow(coordinator: coordinator, recovery: recovery)
        try #require(first !== second)
        try await requireSettings(in: [first, second], fontSize: 23, indentation: 2)

        settings.editor.font.size = 31
        settings.editor.indentationWidth = 8
        try await requireSettings(in: [first, second], fontSize: 31, indentation: 8)
        let later = try makeWindow(coordinator: coordinator, recovery: recovery)
        try await requireSettings(in: [first, second, later], fontSize: 31, indentation: 8)
        #expect(store.editor.font.size == 31)
        #expect(store.editor.indentationWidth == 8)
    }

    private func makeWindow(coordinator: WindowCoordinator, recovery: RecoveryBuffer) throws -> WindowController {
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "Settings fixture\n", recoveryBuffer: recovery))
        let tabID = try #require(model.tabStore.activeTab?.id)
        model.tabStore.setPreviewLayout(.editorOnly, for: tabID)
        let controller = WindowController(
            model: model, coordinator: coordinator, themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry, fileTreePreferences: coordinator.fileTreePreferences
        )
        coordinator.controllers.append(controller)
        return controller
    }

    private func requireSettings(in controllers: [WindowController], fontSize: CGFloat,
                                 indentation: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            var matches = true
            for controller in controllers {
                let window = try #require(controller.window)
                window.contentView?.layoutSubtreeIfNeeded()
                let tab = try #require(controller.model.tabStore.activeTab)
                let system = try #require(controller.editorStore.existingSystem(for: tab.id.uuidString))
                matches = matches && !system.isDetachedFromEditorView && system.textView.font?.pointSize == fontSize
                    && system.editingAssistConfiguration.indentationWidth == indentation
            }
            if matches {
                return
            }
            try #require(ContinuousClock.now < deadline,
                         "Every actual document root must receive initial and changed shared settings")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

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

/// Direct adapter fixtures keep a real controller/editor while omitting the separate workspace producer.
extension TextFilterCoordinatorTests {
    static func makeController(text: String = "one two", mountWorkspace: Bool = true) throws -> Fixture {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        let document = FileDocument(text: text)
        model.tabStore.newTab(document: document)
        let tabID = try #require(model.tabStore.activeTab).id
        let content: NSViewController?
        if mountWorkspace {
            content = nil
        } else {
            let empty = NSViewController()
            empty.view = NSView()
            content = empty
        }
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            initialContentController: content
        )
        coordinator.controllers = [controller]
        controller.editorStore.existingSystem(for: tabID.uuidString)?.setAwaitingEditorView(false) // no EditorView here
        return Fixture(coordinator: coordinator, controller: controller, tabID: tabID)
    }
}

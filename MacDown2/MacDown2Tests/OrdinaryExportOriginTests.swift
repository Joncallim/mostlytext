import AppKit
import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
@Suite("Ordinary export origin")
struct OrdinaryExportOriginTests {
    @Test func panelReadsLatestValueFromOriginalDocumentOnly() throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "before panel"))
        let controller = WindowController(
            model: model, coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        let origin = try #require(OrdinaryExportOrigin.capture(controller: controller))
        model.tabStore.updateActiveDocument { $0.updatingText("edited during panel") }
        let accepted = try origin.documentAfterPanel()
        #expect(accepted.text == "edited during panel")
        model.tabStore.updateActiveDocument { $0.updatingText("later edit") }
        #expect(accepted.text == "edited during panel")

        model.tabStore.updateActiveDocument { _ in FileDocument(text: "replacement") }
        #expect(throws: CancellationError.self) { try origin.documentAfterPanel() }
    }

    @Test func changingToAnotherTabCannotBorrowTheOldExportPanel() throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "A"))
        let controller = WindowController(
            model: model, coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        let origin = try #require(OrdinaryExportOrigin.capture(controller: controller))
        model.tabStore.newTab(document: FileDocument(text: "B"))
        #expect(throws: CancellationError.self) { try origin.documentAfterPanel() }
    }

    @Test func closingOriginCompletesDiagnosticSessionWithoutFinderReveal() async throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "A"))
        let controller = WindowController(
            model: model, coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        defer {
            coordinator.removeController(controller)
            if !controller.isClosed {
                controller.close()
            }
        }

        let window = try #require(controller.window)
        let origin = try #require(OrdinaryExportOrigin.capture(controller: controller))
        #expect(origin.canRevealOutput(isCancelled: false))
        #expect(!origin.canRevealOutput(isCancelled: true))

        // The AppKit sheet need not be shown to prove that a close completes
        // its one-shot continuation and disallows the following Finder action.
        let session = OrdinaryExportAlertSession(alert: NSAlert(), window: window)
        let closeObserver = session.observeOriginClose()
        defer { NotificationCenter.default.removeObserver(closeObserver) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            #expect(session.install(continuation))
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        }
        #expect(!origin.canRevealOutput(isCancelled: false))
    }
}

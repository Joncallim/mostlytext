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

/// Every close path retires the recovery lifetime (async I/O) and then closes. Text typed in that gap used to be
/// discarded without a prompt on the discard/save/conflict/deleted-file paths; only the clean path rechecked.
@MainActor
struct CloseAfterRetireTests {
    private final class CloseRequestProbe: NSObject, NSWindowDelegate {
        var attempts = 0
        func windowShouldClose(_: NSWindow) -> Bool {
            attempts += 1
            return false
        }
    }

    private func makeController() throws -> (coordinator: WindowCoordinator, controller: WindowController) {
        let defaults = try #require(UserDefaults(suiteName: "close-after-retire-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "one"))
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return (coordinator, controller)
    }

    @Test func anUnchangedDocumentClosesTheWindow() async throws {
        let (coordinator, controller) = try makeController()
        let retired = try #require(controller.model.activeDocument)

        await controller.closeAfterRetire(of: retired)

        #expect(coordinator.controllers.isEmpty)
    }

    @Test func textTypedAfterTheRetireKeepsTheWindowOpen() async throws {
        let (coordinator, controller) = try makeController()
        let retired = try #require(controller.model.activeDocument)
        controller.model.tabStore.updateActiveDocument { $0.updatingText("one, then typed") }
        let closeRequest = CloseRequestProbe()
        let window = try #require(controller.window)
        window.delegate = closeRequest
        defer {
            window.delegate = controller
            coordinator.removeController(controller)
            controller.close()
        }

        await controller.closeAfterRetire(of: retired)

        #expect(coordinator.controllers.contains { $0 === controller })
        #expect(controller.model.activeDocument?.text == "one, then typed")
        #expect(closeRequest.attempts == 1, "changed content must request the close flow again")
        #expect(controller.model.activeDocument?.recoveryEpoch != retired.recoveryEpoch)
    }

    /// The generation moves on (an edit made and then reverted to identical text, standing in for a background
    /// reconcile that bumps it) but the text, state and recovery lifetime are unchanged: the window must still close.
    /// The real reconcile is covered by `DeletedDocumentDiscardTests`, repeated under -run-tests-until-failure.
    @Test func aGenerationBumpWithoutATextStateOrLifetimeChangeStillClosesTheWindow() async throws {
        let (coordinator, controller) = try makeController()
        controller.model.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        let retired = try #require(controller.model.activeDocument)
        controller.model.tabStore.updateActiveDocument { $0.updatingText("other").updatingText("dirty") }
        let after = try #require(controller.model.activeDocument)
        #expect(after.mutationGeneration != retired.mutationGeneration, "the fixture must bump the generation")
        #expect(after.text.isExactlyEqual(to: retired.text) && after.state == retired.state)
        #expect(after.recoveryEpoch == retired.recoveryEpoch)

        await controller.closeAfterRetire(of: retired)

        #expect(coordinator.controllers.isEmpty)
    }
}

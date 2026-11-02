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
struct FolderPanelOriginTests {
    @Test func theMenuChoiceStaysWithItsOriginalDocument() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = fixture.makeController()
        fixture.coordinator.controllers = [first]
        let panel = HeldFolderPanel()
        let choosing = fixture.coordinator.chooseFolder(using: panel)
        defer { choosing.cancel(); Task { await panel.complete(nil) } }
        try #require(await panel.waitForPresentation())
        let second = fixture.makeController()
        fixture.coordinator.controllers.append(second)
        await panel.complete(fixture.root)
        await choosing.value
        #expect(first.model.folderURL == fixture.root)
        #expect(second.model.folderURL == nil)
    }

    @Test func aClosedOriginDoesNotRedirectOrReopenItsFolderChoice() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = fixture.makeController()
        fixture.coordinator.controllers = [first]
        let panel = HeldFolderPanel()
        let choosing = fixture.coordinator.chooseFolder(using: panel)
        defer { choosing.cancel(); Task { await panel.complete(nil) } }
        try #require(await panel.waitForPresentation())
        first.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: first.window))
        fixture.coordinator.removeController(first)
        await panel.complete(fixture.root)
        await choosing.value
        #expect(first.model.folderURL == nil)
        #expect(fixture.coordinator.controllers.isEmpty)
    }

    @Test func anApplicationChoiceCreatesItsOwnWindowAfterALaterDocumentOpens() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let panel = HeldFolderPanel()
        let choosing = fixture.coordinator.chooseFolder(using: panel)
        defer { choosing.cancel(); Task { await panel.complete(nil) } }
        try #require(await panel.waitForPresentation())
        #expect(fixture.coordinator.controllers.isEmpty)
        let later = fixture.makeController()
        fixture.coordinator.controllers = [later]
        await panel.complete(fixture.root)
        await choosing.value
        #expect(later.model.folderURL == nil)
        #expect(fixture.coordinator.controllers.count == 2)
        #expect(fixture.coordinator.controllers.last?.model.folderURL == fixture.root)
    }

    @Test func cancellingAnApplicationChoiceCreatesNoDocument() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.coordinator.chooseFolder(using: NoOpFilePanelProvider()).value
        #expect(fixture.coordinator.controllers.isEmpty)
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let coordinator: WindowCoordinator

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-origin-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let preferences = FileTreePreferences(store: FolderPanelPreferences())
            coordinator = WindowCoordinator(
                recoveryBuffer: RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("recovery")),
                themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
                fileTreePreferences: preferences,
                recentFolderRoots: RecentFolderRoots(preferences: preferences),
                recentFileDocuments: RecentFileDocuments(preferences: preferences), appSettings: AppSettingsModel()
            )
        }

        func makeController() -> WindowController {
            let model = coordinator.makeWindowModel()
            model.tabStore.newTab(document: FileDocument(recoveryBuffer: coordinator.recoveryBuffer))
            return coordinator.makeWindowController(model: model)
        }

        func cleanup() {
            for controller in coordinator.controllers {
                coordinator.removeController(controller)
                controller.close()
            }
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private actor HeldFolderPanel: FilePanelProviding {
    private var response: CheckedContinuation<URL?, Never>?
    private var finished = false

    func chooseFile() -> URL? {
        nil
    }

    func chooseSaveLocation(defaultName _: String, format _: FileFormat) -> URL? {
        nil
    }

    func chooseFolder() async -> URL? {
        guard !finished else { return nil }
        return await withCheckedContinuation { response = $0 }
    }

    func waitForPresentation() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if response != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func complete(_ url: URL?) {
        finished = true
        response?.resume(returning: url)
        response = nil
    }
}

@MainActor
private final class FolderPanelPreferences: FileTreePreferenceStoring {
    var filter = FileTreeFilter()
    var opensOnSingleClick = false
    var recentRootBookmarks: [Data] = []
    var recentFileBookmarks: [Data] = []
}

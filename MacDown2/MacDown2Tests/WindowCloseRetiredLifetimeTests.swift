import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// Round-3 review P2: Discard (or Save) in the close sheet retires the lifetime successfully; text typed while that
/// retire
/// awaits makes `closeAfterRetire` keep the window open, but on the RETIRED lifetime.
@MainActor
struct WindowCloseRetiredLifetimeTests {
    private final class CloseRequestProbe: NSObject, NSWindowDelegate {
        var attempts = 0
        func windowShouldClose(_: NSWindow) -> Bool {
            attempts += 1
            return false
        }
    }

    @Test func anEditDuringASuccessfulCloseRetireLeavesTheWindowRecoverable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("tabs.json")),
            recoveryBuffer: buffer
        )
        let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        let helpers = ExternalFileControllerRecoveryTests()
        let coordinator = try #require(helpers.makeCoordinator(directory: directory, recoveryBuffer: buffer))
        let controller = helpers.makeWindowController(model: model, coordinator: coordinator)
        coordinator.controllers = [controller]
        let closeRequest = CloseRequestProbe()
        let window = try #require(controller.window)
        window.delegate = closeRequest
        defer {
            window.delegate = controller
            coordinator.removeController(controller)
            controller.close()
        }
        #expect(await document.persistRecovery())

        // Discard button: retire succeeds ...
        #expect(await controller.externalFileController.retireRecovery(for: document, resumeCloseOnSuccess: true)
            .isAbsent)
        // ... while the user typed in the gap.
        model.tabStore.updateActiveDocument { $0.updatingText("typed during the retire") }
        await controller.closeAfterRetire(of: document)
        #expect(coordinator.controllers.contains { $0 === controller })
        #expect(closeRequest.attempts == 1, "edited content must request the close flow again")
        #expect(model.activeDocument?.recoveryEpoch != document.recoveryEpoch)
        #expect(window.attachedSheet == nil)

        // The window is open with unsaved text. Its recovery must still be writable.
        let current = try #require(model.activeDocument)
        #expect(await current.persistRecovery(), "open dirty window left on a retired recovery lifetime")
        let result = await coordinator.saveSessionResult(isAutosave: true)
        if case .recoveryFailed = result {
            Issue.record("session autosave fails for every window while this one stays open")
        }
        let relaunched = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        #expect(try await relaunched.load(for: current.id, epoch: current.recoveryEpoch) == "typed during the retire")
    }
}

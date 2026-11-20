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

/// A deleted-file sheet may return after the window's active document or
/// recovery lifetime changed. Its buttons can act only on the state shown.
@MainActor
struct DeletedDocumentDiscardTests {
    @MainActor private struct Fixture {
        let root: URL
        let buffer: RecoveryBuffer
        let coordinator: WindowCoordinator
        let controller: WindowController
        let window: NSWindow
        let dirty: FileDocument
        let tabID: UUID
        let presented: CloseSheetContext

        func cleanUp() {
            coordinator.removeController(controller)
            if !controller.isClosed {
                controller.close()
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        let tabID = try #require(model.tabStore.activeTabID)
        let controller = WindowController(
            model: model, coordinator: coordinator, themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry, fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        let window = try #require(controller.window)
        #expect((window as? DocumentWindow)?.documentRepresentedURL == file)
        return Fixture(root: root, buffer: buffer, coordinator: coordinator, controller: controller,
                       window: window,
                       dirty: dirty, tabID: tabID, presented: CloseSheetContext(dirty))
    }

    @Test func discardingThePresentedDocumentRetiresItsRecoveryAndClosesTheWindow() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        #expect(try await fixture.buffer.load(for: fixture.dirty.id, epoch: fixture.dirty.recoveryEpoch)
            == "unsaved words")

        await fixture.coordinator.discardDeletedDocument(
            in: fixture.controller, window: fixture.window,
            tabID: fixture.tabID, presented: fixture.presented
        )

        #expect(fixture.coordinator.controllers.isEmpty)
        #expect(try await fixture.buffer.load(for: fixture.dirty.id, epoch: fixture.dirty.recoveryEpoch) == nil)
    }

    @Test func staleSheetCannotDiscardAReplacementActiveDocument() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let other = FileDocument(text: "second", recoveryBuffer: fixture.buffer).updatingText("other unsaved words")
        #expect(await other.persistRecovery())
        fixture.controller.model.tabStore.newTab(document: other)

        await fixture.coordinator.discardDeletedDocument(
            in: fixture.controller, window: fixture.window,
            tabID: fixture.tabID, presented: fixture.presented
        )

        #expect(fixture.coordinator.controllers.contains(where: { $0 === fixture.controller }))
        #expect(fixture.controller.model.activeDocument?.id == other.id)
        #expect(try await fixture.buffer.load(for: other.id, epoch: other.recoveryEpoch) == "other unsaved words")
        #expect(try await fixture.buffer.load(for: fixture.dirty.id, epoch: fixture.dirty.recoveryEpoch)
            == "unsaved words")
    }

    @Test func staleSheetCannotDiscardLaterEditsToTheSameDocument() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        fixture.controller.model.tabStore.updateActiveDocument { $0.updatingText("typed after the sheet") }
        let later = try #require(fixture.controller.model.activeDocument)
        #expect(await later.persistRecovery())

        await fixture.coordinator.discardDeletedDocument(
            in: fixture.controller, window: fixture.window,
            tabID: fixture.tabID, presented: fixture.presented
        )

        #expect(fixture.coordinator.controllers.contains(where: { $0 === fixture.controller }))
        #expect(fixture.controller.model.activeDocument?.text == "typed after the sheet")
        #expect(try await fixture.buffer.load(for: later.id, epoch: later.recoveryEpoch)
            == "typed after the sheet")
    }

    @Test func staleSheetCannotDiscardARenewedRecoveryLifetime() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let renewed = try await fixture.dirty.withFreshRecoveryLifetime(preparedBy: fixture.buffer)
        fixture.controller.model.tabStore.updateActiveDocument { _ in renewed }
        #expect(await renewed.persistRecovery())

        await fixture.coordinator.discardDeletedDocument(
            in: fixture.controller, window: fixture.window,
            tabID: fixture.tabID, presented: fixture.presented
        )

        #expect(fixture.coordinator.controllers.contains(where: { $0 === fixture.controller }))
        #expect(fixture.controller.model.activeDocument?.recoveryEpoch == renewed.recoveryEpoch)
        #expect(try await fixture.buffer.load(for: renewed.id, epoch: renewed.recoveryEpoch) == "unsaved words")
    }

    @Test func revealAlertCannotChangeTheFolderAfterDocumentOrRootReplacement() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let url = try #require(fixture.dirty.fileURL)
        let context = fixture.controller.fileTreeModel.beginOperation()
        #expect(fixture.coordinator.revealOutsideRootIsCurrent(
            for: url, documentID: fixture.dirty.id, controller: fixture.controller,
            window: fixture.window, context: context
        ))

        fixture.controller.model.tabStore.newTab(document: FileDocument(text: "replacement"))
        #expect(!fixture.coordinator.revealOutsideRootIsCurrent(
            for: url, documentID: fixture.dirty.id, controller: fixture.controller,
            window: fixture.window, context: context
        ))

        fixture.controller.model.tabStore.activate(fixture.tabID)
        await fixture.controller.fileTreeModel.setRoot(fixture.root)
        #expect(!fixture.coordinator.revealOutsideRootIsCurrent(
            for: url, documentID: fixture.dirty.id, controller: fixture.controller,
            window: fixture.window, context: context
        ))
    }
}

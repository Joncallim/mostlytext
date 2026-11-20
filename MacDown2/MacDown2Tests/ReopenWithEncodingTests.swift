import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// EPIC-22 §6.17 / #183 F17 — Reopen with Encoding at the controller boundary.
@MainActor
@Suite("ExternalFileController.reopenWithEncoding")
struct ReopenWithEncodingTests {
    private struct Fixture {
        let controller: WindowController
        let coordinator: WindowCoordinator
        let model: WorkspaceModel
        let directory: URL
    }

    private func makeFixture(bytes: Data) throws -> Fixture {
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
        try model.tabStore.newTab(document: FileDocument(fileURL: url).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return Fixture(controller: controller, coordinator: coordinator, model: model, directory: directory)
    }

    @Test func reopeningWithTheCurrentEncodingIsANoOpEvenWhenDirty() async throws {
        let fixture = try makeFixture(bytes: Data("héllo".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.model.tabStore.updateActiveDocument { $0.updatingText("héllo, edited") }
        let before = fixture.model.activeDocument
        var asked = false

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.utf8) { _ in
            asked = true
            return true
        }

        #expect(result == .unchanged)
        #expect(!asked)
        #expect(fixture.model.activeDocument?.text == "héllo, edited")
        #expect(fixture.model.activeDocument?.state == before?.state)
        #expect(fixture.model.activeDocument?.recoveryEpoch == before?.recoveryEpoch)
    }

    @Test func theWindowLevelEntryPointAlsoDoesNothingForTheCurrentEncoding() async throws {
        let fixture = try makeFixture(bytes: Data("héllo".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.model.tabStore.updateActiveDocument { $0.updatingText("edited") }

        await fixture.controller.reopenDocument(withEncoding: .utf8)

        #expect(fixture.model.activeDocument?.text == "edited")
        #expect(fixture.model.activeDocument?.state == .dirty)
    }

    @Test func aDifferentEncodingRedecodesACleanDocument() async throws {
        let fixture = try makeFixture(bytes: Data("é".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .reopened)
        #expect(fixture.model.activeDocument?.text == "Ã©")
        #expect(fixture.model.activeDocument?.encoding.encoding == .isoLatin1)
    }

    @Test func aDifferentEncodingNeverDiscardsDirtyTextWithoutConfirmation() async throws {
        let fixture = try makeFixture(bytes: Data("é".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.model.tabStore.updateActiveDocument { $0.updatingText("my edits") }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in false }

        #expect(result == .declined)
        #expect(fixture.model.activeDocument?.text == "my edits")
    }

    @Test func anInvalidatedChoiceCannotReloadAfterTheDiscardConfirmation() async throws {
        let fixture = try makeFixture(bytes: Data("é".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.model.tabStore.updateActiveDocument { $0.updatingText("my edits") }
        let origin = try #require(DocumentActionAuthority(model: fixture.model))
        let dirtyDocument = try #require(fixture.model.activeDocument)

        let result = await fixture.controller.externalFileController.reopenWithEncoding(
            .isoLatin1,
            confirmDiscardingChanges: { _ in
                // A new tab can expose the same file/document lifetime. The
                // underlying reload's ID/epoch/generation checks all still match.
                fixture.model.tabStore.newTab(document: dirtyDocument)
                return true
            },
            stillAuthorized: { origin.isCurrent(in: fixture.controller) }
        )

        #expect(result == .superseded)
        #expect(fixture.model.activeDocument?.text == "my edits")
        #expect(fixture.model.activeDocument?.encoding.encoding == .utf8)
    }

    @Test func openingAnAlreadyOpenFileWithAnEncodingRereadsItThroughTheReopenPath() async throws {
        let fixture = try makeFixture(bytes: Data("é".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let url = fixture.directory.appendingPathComponent("doc.txt")

        await fixture.coordinator.performOpenDocument(
            at: url,
            encoding: FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        )

        #expect(fixture.model.activeDocument?.text == "Ã©")
        #expect(fixture.model.activeDocument?.encoding.encoding == .isoLatin1)
    }
}

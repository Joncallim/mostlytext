import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// #17 R01 and document action lifetime: the status bar uses its owning
/// window, while delayed menu and status-bar choices retain their document.
@MainActor
struct StatusBarEncodingOriginTests {
    private func makeCoordinator(recovery: RecoveryBuffer) -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            sessionStore: NoOpSessionStore(),
            recoveryBuffer: recovery,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    private func addWindow(
        to coordinator: WindowCoordinator,
        file: URL,
        recovery: RecoveryBuffer
    ) throws -> WindowController {
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: file, recoveryBuffer: recovery).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences()
        )
        coordinator.controllers.append(controller)
        return controller
    }

    @Test func saveWithEncodingActsOnTheOwningWindowNotTheKeyOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(recovery: recovery)
        let fileA = directory.appendingPathComponent("a.txt")
        let fileB = directory.appendingPathComponent("b.txt")
        try "alpha".write(to: fileA, atomically: true, encoding: .utf8)
        try "bravo".write(to: fileB, atomically: true, encoding: .utf8)
        let windowA = try addWindow(to: coordinator, file: fileA, recovery: recovery)
        let windowB = try addWindow(to: coordinator, file: fileB, recovery: recovery)
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)

        // Neither window is key in a test, so the old key-window routing would
        // have done nothing; routed by owner, B's bar changes B only.
        let origin = try #require(DocumentActionAuthority(model: windowB.model))
        coordinator.saveDocument(in: windowB.model, withEncoding: latin1, origin: origin)
        for _ in 0 ..< 500 where windowB.model.activeDocument?.encoding != latin1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(windowB.model.activeDocument?.encoding == latin1)
        #expect(windowA.model.activeDocument?.encoding == .utf8Default)
    }

    @Test func queuedSaveWithEncodingDoesNotFollowAReplacementDocument() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(recovery: recovery)
        let first = directory.appendingPathComponent("first.txt")
        let replacement = directory.appendingPathComponent("replacement.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "replacement".write(to: replacement, atomically: true, encoding: .utf8)
        let controller = try addWindow(to: coordinator, file: first, recovery: recovery)
        let origin = try #require(DocumentActionAuthority(model: controller.model))
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)

        let pending = Task { await controller.saveDocument(withEncoding: latin1, origin: origin) }
        try controller.model.tabStore
            .newTab(document: FileDocument(fileURL: replacement, recoveryBuffer: recovery).load())
        await pending.value

        #expect(controller.model.activeDocument?.fileURL == replacement)
        #expect(controller.model.activeDocument?.encoding == .utf8Default)
        #expect(try Data(contentsOf: replacement) == Data("replacement".utf8))
        #expect(try Data(contentsOf: first) == Data("first".utf8))
    }

    @Test func queuedOrdinarySaveDoesNotWriteAReplacementDocument() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(recovery: recovery)
        let first = directory.appendingPathComponent("first.txt")
        let replacement = directory.appendingPathComponent("replacement.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "replacement".write(to: replacement, atomically: true, encoding: .utf8)
        let controller = try addWindow(to: coordinator, file: first, recovery: recovery)

        let origin = try #require(DocumentActionAuthority(model: controller.model))
        let pending = Task { await controller.saveDocumentFromExplicitOrigin(origin: origin) }
        try controller.model.tabStore.newTab(document: FileDocument(fileURL: replacement, recoveryBuffer: recovery)
            .load().updatingText("replacement draft"))
        await pending.value

        #expect(controller.model.activeDocument?.text == "replacement draft")
        #expect(controller.model.activeDocument?.state == .dirty)
        #expect(try Data(contentsOf: replacement) == Data("replacement".utf8))
    }

    @Test func staleReopenChoiceCannotRedecodeAReplacementDocument() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(recovery: recovery)
        let first = directory.appendingPathComponent("first.txt")
        let replacement = directory.appendingPathComponent("replacement.txt")
        try Data("é".utf8).write(to: first)
        try Data("é".utf8).write(to: replacement)
        let controller = try addWindow(to: coordinator, file: first, recovery: recovery)
        let origin = try #require(DocumentActionAuthority(model: controller.model))

        try controller.model.tabStore
            .newTab(document: FileDocument(fileURL: replacement, recoveryBuffer: recovery).load())
        coordinator.reopenDocument(in: controller.model, withEncoding: .isoLatin1, origin: origin)
        await controller.reopenDocument(withEncoding: .isoLatin1, origin: origin)

        #expect(controller.model.activeDocument?.fileURL == replacement)
        #expect(controller.model.activeDocument?.text == "é")
        #expect(controller.model.activeDocument?.encoding.encoding == .utf8)
    }
}

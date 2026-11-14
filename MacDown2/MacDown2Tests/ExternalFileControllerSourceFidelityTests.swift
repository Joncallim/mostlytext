import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// Deterministic controller checks with real file bytes. The UI suite covers
/// presentation; these cases pin the model/editor/disk result of each action.
@MainActor
@Suite("External-file source fidelity", .serialized)
struct ExternalSourceFidelityTests {
    @MainActor
    private struct Fixture {
        let directory: URL
        let url: URL
        let model: WorkspaceModel
        let editor: EditorTextSystem
        let controller: ExternalFileController

        func close() {
            controller.dispose()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func fixture(original: String) throws -> Fixture {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("mostlytext-source-fidelity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("document.md")
        try Data(original.utf8).write(to: url)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = try FileDocument(fileURL: url, recoveryBuffer: recovery).load()
        let tabs = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: recovery
        )
        tabs.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabs)
        let identity = UUID().uuidString
        let editorStore = EditorTextSystemStore()
        let editor = editorStore.system(for: identity, initialText: original, configuration: .default)
        let controller = ExternalFileController(model: model, editorStore: editorStore, identity: identity)
        controller.boundURL = url.standardizedFileURL
        return Fixture(directory: directory, url: url, model: model, editor: editor, controller: controller)
    }

    private func waitUntil(_ description: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(description)")
        throw CancellationError()
    }

    @Test func cleanInPlaceWriteReloadsExactBytesAndClampsSelection() async throws {
        let original = "# Original\r\n\r\nlast line\r\n"
        let newText = "# Disk\r\n"
        let fixture = try fixture(original: original)
        defer { fixture.close() }
        let oldSelection = NSRange(location: (original as NSString).length - 2, length: 2)
        fixture.editor.selectedRange = oldSelection
        try Data(newText.utf8).write(to: fixture.url, options: [])
        let document = try #require(fixture.model.activeDocument)
        let snapshot = try document.fileStore.readSnapshot(from: fixture.url)
        fixture.controller.handle(.available(snapshot))
        try await waitUntil("clean in-place reload") {
            fixture.model.activeDocument?.text.isExactlyEqual(to: newText) == true
                && fixture.editor.textView.string.isExactlyEqual(to: newText)
        }
        #expect(fixture.model.activeDocument?.state == .clean)
        #expect(fixture.controller.latestExternalSnapshot == nil)
        #expect(fixture.controller.notice == .reloaded)
        #expect(fixture.editor.selectedRange.location <= (newText as NSString).length)
        #expect(NSMaxRange(fixture.editor.selectedRange) <= (newText as NSString).length)
        #expect(try Data(contentsOf: fixture.url) == Data(newText.utf8))
        #expect(fixture.model.activeDocument?.encoding.encoding == .utf8)
    }

    @Test func keepMineThenSavePublishesLocalBytesWithoutAnOwnSaveConflict() async throws {
        let original = "# Base\r\n"
        let mine = "# Mine\r\nlocal café\r\n"
        let theirs = "# Theirs\r\n"
        let fixture = try fixture(original: original)
        defer { fixture.close() }
        fixture.model.tabStore.updateActiveDocument { $0.updatingText(mine) }
        fixture.editor.textView.string = mine
        fixture.editor.selectedRange = NSRange(location: 3, length: 0)
        try Data(theirs.utf8).write(to: fixture.url, options: [])
        let document = try #require(fixture.model.activeDocument)
        let snapshot = try document.fileStore.readSnapshot(from: fixture.url)
        fixture.controller.handle(.available(snapshot))
        try await waitUntil("dirty conflict") {
            fixture.model.activeDocument?.state == .conflict
                && fixture.controller.notice == .conflict
        }
        #expect(fixture.model.activeDocument?.text.isExactlyEqual(to: mine) == true)
        #expect(fixture.editor.textView.string.isExactlyEqual(to: mine))
        #expect(try Data(contentsOf: fixture.url) == Data(theirs.utf8))

        await fixture.controller.resolveConflict(.keepMine)
        #expect(fixture.model.activeDocument?.state == .dirty)
        #expect(fixture.model.activeDocument?.text.isExactlyEqual(to: mine) == true)
        #expect(fixture.editor.textView.string.isExactlyEqual(to: mine))
        #expect(fixture.controller.notice == .none)
        #expect(fixture.editor.selectedRange == NSRange(location: 3, length: 0))
        #expect(try Data(contentsOf: fixture.url) == Data(theirs.utf8))

        #expect(await fixture.model.saveWithoutDestinationPrompt() == .handled)
        fixture.controller.synchronize(with: fixture.model.activeDocument)
        try await waitUntil("local save") { fixture.model.activeDocument?.state == .clean }
        #expect(try Data(contentsOf: fixture.url) == Data(mine.utf8))
        let saved = try #require(fixture.model.activeDocument)
        let ownSnapshot = try saved.fileStore.readSnapshot(from: fixture.url)
        fixture.controller.handle(.available(ownSnapshot))
        try await waitUntil("own-save observation") {
            fixture.model.activeDocument?.lastKnownRevision?.sha256 == ownSnapshot.revision.sha256
        }
        #expect(fixture.model.activeDocument?.state == .clean)
        #expect(fixture.model.activeDocument?.text.isExactlyEqual(to: mine) == true)
        #expect(fixture.editor.textView.string.isExactlyEqual(to: mine))
        #expect(fixture.controller.notice != .conflict)
        #expect(fixture.controller.latestExternalSnapshot == nil)
        #expect(fixture.editor.selectedRange == NSRange(location: 3, length: 0))
    }
}

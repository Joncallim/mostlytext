@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// A save panel is open for as long as the user takes to answer it, and the
/// active document can change underneath it — an external-change reload
/// replaces it, or another tab is activated. Neither is blocked by a sheet.
///
/// `saveAs(to:expecting:)` therefore writes the document the Save As was
/// *started for*, and abandons the save if that document is no longer the
/// active one. These tests pin that: the split into a panel-presenting
/// `saveAs()` plus a URL-taking `saveAs(to:expecting:)` (so the command
/// palette could bind its own panel to an explicit origin window) briefly
/// dropped the guard by re-reading `tabStore.activeDocument` after the panel
/// and checking `isCurrent` against it — a comparison of the active document
/// with itself, which is always true.
@MainActor
@Suite("WorkspaceModel Save As destination expectation")
struct WorkspaceModelSaveAsExpectationTests {
    @Test func saveAsAdmissionRejectsAReplacementWithTheSameVisibleState() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        _ = try FileStore().write("same text", to: source)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load())
        let tabID = try #require(tabStore.activeTab).id
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())
        let original = try #require(model.activeDocument)
        let admission = try #require(model.reserveSaveAs(for: original))
        defer { model.finishSaveAs(admission) }

        let replacement = try FileDocument(fileURL: source).load()
        #expect(replacement.id == original.id)
        #expect(replacement.text == original.text)
        #expect(replacement.mutationGeneration == original.mutationGeneration)
        #expect(replacement.recoveryEpoch != original.recoveryEpoch)
        tabStore.updateActiveDocument { _ in replacement }

        #expect(!model.isAdmittedSaveAsCurrent(admission, for: original))
        #expect(!model.isCurrent(original, inTab: tabID))
    }

    @Test func destinationPanelOwnsTheSaveAsAdmissionUntilItReturns() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("draft", to: source)
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load().updatingText("edited"))
        var model: WorkspaceModel?
        let panel = InterposingPanelProvider(destination: destination) {
            guard let model, let active = model.activeDocument else {
                Issue.record("Save As lost its document while the panel was open")
                return
            }
            #expect(model.reserveSaveAs(for: active) == nil)
        }
        model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model?.saveAs()

        #expect(try FileStore().read(from: destination).content == "edited")
    }

    /// The damaging case: the user picks a filename for document A, and B is
    /// active by the time the panel returns. Writing B's contents to the name
    /// chosen for A — and rebinding B to it — must not happen.
    @Test func saveAsDoesNotWriteADifferentDocumentThatBecameActiveWhileThePanelWasUp() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let sourceA = directory.appendingPathComponent("a.md")
        let sourceB = directory.appendingPathComponent("b.md")
        let destination = directory.appendingPathComponent("chosen-for-a.md")
        _ = try FileStore().write("alpha", to: sourceA)
        _ = try FileStore().write("beta", to: sourceB)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: sourceA).load())
        let tabA = try #require(tabStore.activeTab).id
        try tabStore.newTab(document: FileDocument(fileURL: sourceB).load())
        let tabB = try #require(tabStore.activeTab).id
        tabStore.activate(tabA)
        #expect(tabStore.activeDocument?.fileURL?.standardizedFileURL == sourceA.standardizedFileURL)

        let panel = InterposingPanelProvider(destination: destination) {
            tabStore.activate(tabB)
        }
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(
            !FileManager.default.fileExists(atPath: destination.path),
            "B's contents must not be written to the destination the user chose for A"
        )
        #expect(
            model.activeDocument?.fileURL?.standardizedFileURL == sourceB.standardizedFileURL,
            "B must not be rebound to a destination chosen for a different document"
        )
        #expect(try FileStore().read(from: sourceA).content == "alpha")
        #expect(try FileStore().read(from: sourceB).content == "beta")
    }

    /// #183 F22: the destination is captured as a baseline when the user
    /// authorises it, and publication is conditional on it. A file another
    /// process creates in between is never overwritten.
    @Test func saveAsDoesNotOverwriteADestinationCreatedAfterAuthorization() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("on disk", to: source)
        let racingStore = FileStore(afterBaselineVerification: { url in
            if url.standardizedFileURL == destination.standardizedFileURL {
                try Data("external winner".utf8).write(to: url)
            }
        })

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source, fileStore: racingStore).load())
        let model = WorkspaceModel(
            tabStore: tabStore,
            stateStore: FakeStateStore(),
            panel: InterposingPanelProvider(destination: destination) {}
        )

        await model.saveAs()

        #expect(try FileStore().read(from: destination).content == "external winner")
        #expect(model.lastError != nil)
        #expect(model.activeDocument?.fileURL?.standardizedFileURL == source.standardizedFileURL)
    }

    @Test func saveAsOverwritesAnExistingDestinationThatIsUnchangedSinceAuthorization() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("on disk", to: source)
        _ = try FileStore().write("old destination", to: destination)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load())
        let model = WorkspaceModel(
            tabStore: tabStore,
            stateStore: FakeStateStore(),
            panel: InterposingPanelProvider(destination: destination) {}
        )

        await model.saveAs()

        #expect(try FileStore().read(from: destination).content == "on disk")
        #expect(model.lastError == nil)
    }

    /// The same guard for the more ordinary case: the *same* document is
    /// replaced (an external-change reload) while the panel is up.
    @Test func saveAsAbandonsTheSaveIfItsOwnDocumentWasReplacedWhileThePanelWasUp() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("on disk", to: source)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load())
        let panel = InterposingPanelProvider(destination: destination) {
            tabStore.updateActiveDocument { $0.edited(text: "reloaded from disk") }
        }
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(model.activeDocument?.fileURL?.standardizedFileURL == source.standardizedFileURL)
    }

    /// Control: nothing changes under the panel, so the save proceeds.
    @Test func saveAsWritesTheDocumentItWasStartedForWhenNothingChanges() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("content", to: source)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load())
        let panel = InterposingPanelProvider(destination: destination) {}
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(model.activeDocument?.fileURL?.standardizedFileURL == destination.standardizedFileURL)
        #expect(try FileStore().read(from: destination).content == "content")
    }

    /// Save As onto a symbolic-link name failed with a misleading "file doesn't exist" (link to a file)
    /// or "item already exists" (dangling link). It now writes through to the link's target.
    @Test func saveAsOntoASymbolicLinkWritesThroughToItsTarget() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let target = directory.appendingPathComponent("target.md")
        let link = directory.appendingPathComponent("link.md")
        _ = try FileStore().write("draft", to: source)
        _ = try FileStore().write("old target", to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load().updatingText("new content"))
        let panel = InterposingPanelProvider(destination: link, duringPanel: {})
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)
        let expected = try #require(model.activeDocument)

        await model.saveAs(to: link, expecting: expected)

        #expect(model.lastError == nil)
        #expect(try FileStore().read(from: target).content == "new content")
        #expect((try? link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true)
        #expect(model.activeDocument?.fileURL?.standardizedFileURL == target.standardizedFileURL)
    }

    /// Typing while the destination is being read (off the main actor) used to make the explicit Save As silently
    /// do nothing: the post-await `isCurrent(expected)` guard failed on the edited document with no error.
    @Test func typingWhileTheDestinationIsReadDoesNotCancelSaveAs() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("draft", to: source)
        // A large existing destination keeps the off-main baseline read busy long enough to type during it.
        let handle = try { () throws -> FileHandle in
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            return try FileHandle(forWritingTo: destination)
        }()
        try handle.truncate(atOffset: 256 * 1024 * 1024)
        try handle.close()

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load().updatingText("saved text"))
        let panel = InterposingPanelProvider(destination: destination, duringPanel: {})
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)
        let expected = try #require(model.activeDocument)

        let save = Task { @MainActor in await model.saveAs(to: destination, expecting: expected) }
        await Task.yield()
        tabStore.updateActiveDocument { $0.updatingText($0.text + " plus typing") }
        await save.value

        #expect(try String(contentsOf: destination, encoding: .utf8) == "saved text")
        #expect(model.activeDocument?.fileURL?.standardizedFileURL == destination.standardizedFileURL)
        #expect(model.activeDocument?.text == "saved text plus typing")
    }

    @Test func saveAsOntoADanglingSymbolicLinkCreatesItsTarget() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let target = directory.appendingPathComponent("not-yet.md")
        let link = directory.appendingPathComponent("dangling.md")
        _ = try FileStore().write("draft", to: source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: source).load().updatingText("created"))
        let panel = InterposingPanelProvider(destination: link, duringPanel: {})
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)
        let expected = try #require(model.activeDocument)

        await model.saveAs(to: link, expecting: expected)

        #expect(model.lastError == nil)
        #expect(try FileStore().read(from: target).content == "created")
    }
}

/// A panel provider that runs `duringPanel` while the "panel" is up — i.e.
/// after Save As has captured the document it is saving and before it has a
/// URL to save it to. That interval is exactly the one a real sheet leaves
/// open to external-change reloads and tab activations.
private final class InterposingPanelProvider: FilePanelProviding, @unchecked Sendable {
    private let destination: URL
    private let duringPanel: @MainActor () -> Void

    init(destination: URL, duringPanel: @escaping @MainActor () -> Void) {
        self.destination = destination
        self.duringPanel = duringPanel
    }

    func chooseFile() async -> URL? {
        nil
    }

    func chooseFolder() async -> URL? {
        nil
    }

    func chooseSaveLocation(defaultName _: String, format _: FileFormat) async -> URL? {
        await MainActor.run { duringPanel() }
        return destination
    }
}

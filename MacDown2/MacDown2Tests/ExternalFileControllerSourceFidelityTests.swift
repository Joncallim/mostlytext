import Darwin
import EditorCore
@testable import FileCore
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

    private func fixture(
        original: String,
        monitor: DocumentFileMonitor = DocumentFileMonitor()
    ) throws -> Fixture {
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
        let controller = ExternalFileController(
            model: model, editorStore: editorStore, identity: identity, monitor: monitor
        )
        controller.boundURL = url.standardizedFileURL
        return Fixture(directory: directory, url: url, model: model, editor: editor, controller: controller)
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(3),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
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

    @Test func cleanReadFailureThenChangedDiskReloadsWithoutAFalseConflict() async throws {
        let original = "# Original\r\n\r\nlast line\r\n"
        let newText = "# Replaced\r\n"
        let fixture = try fixture(original: original)
        defer { fixture.close() }
        fixture.editor.selectedRange = NSRange(location: (original as NSString).length - 2, length: 2)

        fixture.controller.handle(.unavailable(fixture.url, .readFailed("temporary read failure")))
        try await waitUntil("temporary read failure") {
            fixture.model.activeDocument?.backingState == .unavailable(.readFailed("temporary read failure"))
        }
        #expect(fixture.model.activeDocument?.state == .dirty)
        #expect(fixture.editor.textView.string.isExactlyEqual(to: original))
        await fixture.controller.drainRecovery()
        let unavailable = try #require(fixture.model.activeDocument)
        #expect(try await unavailable.recoveryBuffer.load(
            for: unavailable.id, epoch: unavailable.recoveryEpoch
        ) == original)

        try Data(newText.utf8).write(to: fixture.url, options: .atomic)
        let snapshot = try unavailable.fileStore.readSnapshot(from: fixture.url)
        fixture.controller.handle(.available(snapshot))
        try await waitUntil("clean reload after read failure") {
            fixture.model.activeDocument?.text.isExactlyEqual(to: newText) == true
                && fixture.editor.textView.string.isExactlyEqual(to: newText)
        }

        #expect(fixture.model.activeDocument?.state == .clean)
        #expect(fixture.model.activeDocument?.pendingExternalRevision == nil)
        #expect(fixture.controller.notice == .reloaded)
        #expect(fixture.controller.latestExternalSnapshot == nil)
        #expect(NSMaxRange(fixture.editor.selectedRange) <= (newText as NSString).length)
        #expect(try Data(contentsOf: fixture.url) == Data(newText.utf8))
        await fixture.controller.drainRecovery()
        #expect(try await unavailable.recoveryBuffer.load(
            for: unavailable.id, epoch: unavailable.recoveryEpoch
        ) == nil)
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

extension ExternalSourceFidelityTests {
    @Test func sameParentRenameRetainsTheDocumentAndPublishesItsNewSessionURL() async throws {
        let original = "# Café\r\n\r\nUnchanged text.\r\n"
        let fixture = try fixture(original: original)
        defer { fixture.close() }
        let selection = NSRange(location: 3, length: 4)
        fixture.editor.selectedRange = selection
        fixture.editor.scrollOffset = 25
        let renamed = fixture.directory.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: fixture.url, to: renamed)
        let document = try #require(fixture.model.activeDocument)
        let expectedURL = try #require(document.fileURL)
        let observation = await DocumentFileProbe().observe(
            expectedURL: expectedURL, priorFileObjectID: document.lastKnownRevision?.fileObjectID,
            decoding: document.encoding.decodingPolicy
        )
        guard case let .moved(snapshot) = observation else {
            Issue.record("A same-parent identity-preserving rename was not classified as a move")
            return
        }
        #expect(snapshot.revision.url.standardizedFileURL == renamed.standardizedFileURL)

        fixture.controller.handle(observation)
        try await waitUntil("same-parent move") {
            fixture.model.activeDocument?.fileURL?.standardizedFileURL == renamed.standardizedFileURL
        }

        #expect(fixture.model.activeDocument?.state == .clean)
        #expect(fixture.model.activeDocument?.text.isExactlyEqual(to: original) == true)
        #expect(fixture.editor.textView.string.isExactlyEqual(to: original))
        #expect(fixture.editor.selectedRange == selection)
        #expect(fixture.editor.scrollOffset == 25)
        #expect(try Data(contentsOf: renamed) == Data(original.utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        #expect(await fixture.model.tabStore.saveSession())
        let session = try #require(WorkspaceSessionStore(
            fileURL: fixture.directory.appendingPathComponent("session.json")
        ).loadSession())
        #expect(session.tabs.first?.fileURL?.standardizedFileURL == renamed.standardizedFileURL)
    }

    @Test func crossParentMoveKeepsDirtySourceOnItsUnavailableOriginalPath() async throws {
        let original = "# Original\r\n"
        let mine = "# Local draft\r\n🙂\r\n"
        let fixture = try fixture(original: original)
        defer { fixture.close() }
        fixture.model.tabStore.updateActiveDocument { $0.updatingText(mine) }
        fixture.editor.textView.string = mine
        let selection = NSRange(location: 3, length: 5)
        fixture.editor.selectedRange = selection
        let destinationDirectory = fixture.directory.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let moved = destinationDirectory.appendingPathComponent("document.md")
        try FileManager.default.moveItem(at: fixture.url, to: moved)

        // The file probe only establishes identity in the watched parent.
        // A cross-parent move must retain the local draft and offer recovery.
        let documentBeforeMove = try #require(fixture.model.activeDocument)
        let expectedURL = try #require(documentBeforeMove.fileURL)
        let observation = await DocumentFileProbe().observe(
            expectedURL: expectedURL, priorFileObjectID: documentBeforeMove.lastKnownRevision?.fileObjectID,
            decoding: documentBeforeMove.encoding.decodingPolicy
        )
        #expect(observation == .missing(expectedURL))
        fixture.controller.handle(observation)
        try await waitUntil("cross-parent unavailable state") {
            fixture.model.activeDocument?.backingState == .unavailable(.missingOrMoved)
        }

        let document = try #require(fixture.model.activeDocument)
        #expect(document.state == .dirty)
        #expect(document.fileURL == expectedURL)
        #expect(document.text.isExactlyEqual(to: mine))
        #expect(fixture.editor.textView.string.isExactlyEqual(to: mine))
        #expect(fixture.editor.selectedRange == selection)
        #expect(fixture.controller.notice == .unavailable(.missingOrMoved))
        #expect(try Data(contentsOf: moved) == Data(original.utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        #expect(await fixture.model.tabStore.saveSession())
        let recovered = try await document.recoveryBuffer.load(for: document.id, epoch: document.recoveryEpoch)
        #expect(recovered?.isExactlyEqual(to: mine) == true)
    }

    @Test func deletionKeepsTheLastEditorBytesAndRecoveryCopy() async throws {
        let original = "# Deleted backing\nStill visible.\n"
        let fixture = try fixture(original: original)
        defer { fixture.close() }
        fixture.editor.selectedRange = NSRange(location: 4, length: 7)
        try FileManager.default.removeItem(at: fixture.url)

        let documentBeforeDeletion = try #require(fixture.model.activeDocument)
        let expectedURL = try #require(documentBeforeDeletion.fileURL)
        let observation = await DocumentFileProbe().observe(
            expectedURL: expectedURL, priorFileObjectID: documentBeforeDeletion.lastKnownRevision?.fileObjectID,
            decoding: documentBeforeDeletion.encoding.decodingPolicy
        )
        #expect(observation == .missing(expectedURL))
        fixture.controller.handle(observation)
        try await waitUntil("deleted backing unavailable state") {
            fixture.model.activeDocument?.backingState == .unavailable(.missingOrMoved)
        }

        let document = try #require(fixture.model.activeDocument)
        #expect(document.state == .dirty)
        #expect(document.text.isExactlyEqual(to: original))
        #expect(fixture.editor.textView.string.isExactlyEqual(to: original))
        #expect(fixture.editor.selectedRange == NSRange(location: 4, length: 7))
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        #expect(await fixture.model.tabStore.saveSession())
        let recovered = try await document.recoveryBuffer.load(for: document.id, epoch: document.recoveryEpoch)
        #expect(recovered?.isExactlyEqual(to: original) == true)
    }

    @Test func realAtomicWriteStormConvergesOnTheLastDiskRevision() async throws {
        let fixture = try fixture(original: "# Initial\n")
        defer { fixture.close() }
        fixture.controller.boundURL = nil
        fixture.controller.start()
        await fixture.controller.bindTask?.value
        let originalSelection = NSRange(location: 2, length: 3)
        fixture.editor.selectedRange = originalSelection

        // First prove the live watcher is connected; the burst must then
        // converge through that same production monitor/controller path.
        try atomicReplace("# Positive control\n", at: fixture.url)
        try await waitUntil("positive external replacement", timeout: .seconds(10)) {
            fixture.model.activeDocument?.text.isExactlyEqual(to: "# Positive control\n") == true
        }

        for index in 0 ..< 20 {
            try atomicReplace("# Formatter pass \(index)\n", at: fixture.url)
        }
        let expected = "# Formatter pass 19\n"
        try await waitUntil("last formatter revision", timeout: .seconds(10)) {
            fixture.model.activeDocument?.text.isExactlyEqual(to: expected) == true
                && fixture.editor.textView.string.isExactlyEqual(to: expected)
        }
        let document = try #require(fixture.model.activeDocument)
        let disk = try document.fileStore.readSnapshot(from: fixture.url)
        #expect(document.state == .clean)
        #expect(document.lastKnownRevision?.sha256 == disk.revision.sha256)
        #expect(fixture.controller.latestExternalSnapshot == nil)
        #expect(fixture.editor.selectedRange == originalSelection)
        #expect(try Data(contentsOf: fixture.url) == Data(expected.utf8))
    }

    @Test func disposeDuringRealDeletionDebounceRejectsTheRetiredObservation() async throws {
        let monitor = DocumentFileMonitor(debounce: .seconds(10))
        let original = "# Open draft\n"
        let fixture = try fixture(original: original, monitor: monitor)
        defer { fixture.close() }
        fixture.controller.boundURL = nil
        fixture.controller.start()
        await fixture.controller.bindTask?.value
        let boundGeneration = await monitor.generation
        let initialRequest = await monitor.currentRequestGeneration()

        try FileManager.default.removeItem(at: fixture.url)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline,
              await monitor.currentRequestGeneration() == initialRequest {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pendingRequest = await monitor.currentRequestGeneration()
        #expect(pendingRequest > initialRequest, "real watcher must enter debounce before close")

        fixture.controller.dispose()
        await fixture.controller.bindTask?.value
        // Acknowledge the late delivery path directly after cancellation;
        // waiting in silence would not prove it was unable to publish.
        await monitor.probeAfterSignal(generation: boundGeneration, sequence: pendingRequest)
        #expect(fixture.model.activeDocument?.state == .clean)
        #expect(fixture.model.activeDocument?.text.isExactlyEqual(to: original) == true)
        #expect(fixture.editor.textView.string.isExactlyEqual(to: original))
        #expect(fixture.controller.notice == .none)
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
    }

    private func atomicReplace(_ text: String, at url: URL) throws {
        let staging = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: staging)
        guard rename(staging.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

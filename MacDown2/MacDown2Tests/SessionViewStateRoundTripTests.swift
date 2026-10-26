import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// The coordinator's real session writer/restorer must carry per-tab view
/// state (Preview Mode and Syntax Mode, EPIC-22 Slice 9d) — `TabStore`'s own
/// `currentSession()` is not what the app publishes.
@MainActor
struct SessionViewStateRoundTripTests {
    final class MemorySessionStore: WorkspaceSessionStoring {
        var session: WorkspaceSession?
        var failNextSave = false
        var publicationCount = 0
        func loadSession() -> WorkspaceSession? {
            session
        }

        func saveSession(_ session: WorkspaceSession) {
            if failNextSave {
                failNextSave = false
                return
            }
            publicationCount += 1
            self.session = session
        }
    }

    private func makeCoordinator(sessions: MemorySessionStore, recovery: RecoveryBuffer) -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            sessionStore: sessions,
            recoveryBuffer: recovery,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    @Test func previewModeAndSyntaxModeSurviveSaveAndRestore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let sessions = MemorySessionStore()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(sessions: sessions, recovery: recovery)
        let preferences = FileTreePreferences()

        let model = coordinator.makeWindowModel()
        let document = try FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load()
        model.tabStore.newTab(document: document)
        let tabID = try #require(model.tabStore.activeTabID)
        model.tabStore.setPreviewMode(.source, for: tabID)
        model.tabStore.setSyntaxMode("python", for: tabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]

        #expect(await coordinator.saveSessionResult().persisted)
        let record = try #require(sessions.session?.tabs.first)
        #expect(record.previewMode == .source)
        #expect(record.syntaxOverride == SyntaxModeOverride(modeFormatID: "python", baseFormatID: "plaintext"))

        let restoringStore = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        await restoringStore.restoreSessionIfNeeded()
        let restoredTab = try #require(restoringStore.tabs.first)
        let restoredController = coordinator.makeRestoredController(tab: restoredTab)
        coordinator.applyRestoredState(controller: restoredController, tab: restoredTab)

        let live = try #require(restoredController.model.tabStore.activeTab)
        #expect(live.previewMode == .source)
        #expect(live.syntaxFormat.id == "python")
        #expect(live.document.format.id == restoredTab.document.format.id)
    }

    @Test func sessionSavesTheEditorsPrimarySelectionNotTheTopmostRange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "alpha beta gamma delta".write(to: fileURL, atomically: true, encoding: .utf8)

        let sessions = MemorySessionStore()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(sessions: sessions, recovery: recovery)
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load())
        let tabID = try #require(model.tabStore.activeTabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences()
        )
        coordinator.controllers = [controller]
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 11, length: 5)],
            primaryIndex: 1
        )

        #expect(await coordinator.saveSessionResult().persisted)

        let record = try #require(sessions.session?.tabs.first)
        #expect(record.cursorPosition == 11)
        #expect(record.selectionLength == 5)
    }
}

// MARK: - #183 F20: an obsolete snapshot must not publish the session

extension SessionViewStateRoundTripTests {
    @Test func aScheduledChangeInvalidatesAnUnpublishedSnapshot() {
        var order = SessionPublicationOrder()
        let older = order.beginSnapshot()
        #expect(!order.isSuperseded(older))

        order.invalidateCapturedSnapshots()
        #expect(order.isSuperseded(older))
        let newer = order.beginSnapshot()
        #expect(!order.isSuperseded(newer))
    }

    func coordinatorWithOneTab(
        sessions: MemorySessionStore,
        directory: URL
    ) throws -> WindowCoordinator {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(sessions: sessions, recovery: recovery)
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences()
        )
        coordinator.controllers = [controller]
        return coordinator
    }

    @Test func aCancelledAutosaveNeverPublishesItsObsoleteSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)

        let autosave = Task { @MainActor in await coordinator.saveSessionResult(isAutosave: true) }
        autosave.cancel()
        _ = await autosave.value

        #expect(sessions.session == nil)
    }

    @Test func anAutosaveThatIsNotSupersededPublishes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)

        #expect(await coordinator.saveSessionResult(isAutosave: true).persisted)

        #expect(sessions.session?.tabs.count == 1)
    }

    @Test func anExplicitSaveStillPublishesEvenIfItsTaskWasCancelled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)

        let explicit = Task { @MainActor in await coordinator.saveSessionResult() }
        explicit.cancel()
        _ = await explicit.value

        #expect(sessions.session?.tabs.count == 1)
    }

    /// Suspends the FIRST caller until `release()`; later callers pass straight through.
    @MainActor
    final class FirstCallGate {
        private(set) var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        private var callCount = 0

        func pass() async {
            callCount += 1
            guard callCount == 1 else { return }
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    @Test func anOlderSnapshotFinishingLateNeverRollsBackANewerPublishedSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        let tabID = try #require(controller.model.tabStore.activeTabID)
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        let gate = FirstCallGate()
        coordinator.afterSessionRecoveryPersisted = { await gate.pass() }

        // Snapshot A (caret 0) is taken, then suspends before publishing.
        system.selectionSet = EditorSelectionSet(single: NSRange(location: 0, length: 0))
        let older = Task { @MainActor in await coordinator.saveSessionResult() }
        for _ in 0 ..< 1000 where !gate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(gate.entered)

        // State moves on; snapshot B (caret 3) completes and publishes first.
        system.selectionSet = EditorSelectionSet(single: NSRange(location: 3, length: 0))
        #expect(await coordinator.saveSessionResult().persisted)
        #expect(sessions.session?.tabs.first?.cursorPosition == 3)

        // A resumes last. It must not overwrite the newer session.
        gate.release()
        #expect(await older.value.persisted)
        #expect(sessions.session?.tabs.first?.cursorPosition == 3)
    }

    @Test func aPendingDebouncedChangeInvalidatesAnExplicitSnapshotBeforePublication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        let tabID = try #require(controller.model.tabStore.activeTabID)
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        let gate = FirstCallGate()
        coordinator.afterSessionRecoveryPersisted = { await gate.pass() }

        system.selectionSet = EditorSelectionSet(single: NSRange(location: 0, length: 0))
        let older = Task { @MainActor in await coordinator.saveSessionResult() }
        for _ in 0 ..< 1000 where !gate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(gate.entered)

        system.selectionSet = EditorSelectionSet(single: NSRange(location: 3, length: 0))
        coordinator.scheduleSaveSession()
        gate.release()

        #expect(await older.value.persisted)
        #expect(sessions.session?.tabs.first?.cursorPosition == 3)
    }

    @Test func failedNewerPublicationDoesNotAuthorizeAnOlderSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        let tabID = try #require(controller.model.tabStore.activeTabID)
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        let gate = FirstCallGate()
        coordinator.afterSessionRecoveryPersisted = { await gate.pass() }

        system.selectionSet = EditorSelectionSet(single: NSRange(location: 0, length: 0))
        let older = Task { @MainActor in await coordinator.saveSessionResult() }
        for _ in 0 ..< 1000 where !gate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(gate.entered)

        system.selectionSet = EditorSelectionSet(single: NSRange(location: 3, length: 0))
        sessions.failNextSave = true
        let newerResult = await coordinator.saveSessionResult()
        #expect(!newerResult.persisted)
        #expect(sessions.session == nil)
        gate.release()

        #expect(await older.value.persisted)
        #expect(sessions.session?.tabs.first?.cursorPosition == 3)
    }

    @Test func repeatedInvalidationFailsAnExplicitPublisherWithoutWritingStaleState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        var rejectionCount = 0
        coordinator.afterSessionPublicationRejected = { superseded, documentChanged in
            #expect(superseded)
            #expect(!documentChanged)
            rejectionCount += 1
        }
        coordinator.afterSessionRecoveryPersisted = { [weak coordinator] in
            guard let coordinator else { return }
            coordinator.sessionPublicationOrder.invalidateCapturedSnapshots()
        }

        let result = await coordinator.saveSessionResult()

        #expect(!result.persisted)
        #expect(rejectionCount == 2)
        #expect(sessions.session == nil)
    }

    /// Review pass 1: the canonical session record must carry the document's
    /// encoding/BOM, or a Latin-1/UTF-16 file fails strict UTF-8 on restore.
    @Test func theCanonicalSessionRecordCarriesTheDocumentsEncoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        controller.model.tabStore.updateActiveDocument {
            FileDocument(
                fileURL: $0.fileURL,
                text: $0.text,
                encoding: latin1,
                recoveryBuffer: $0.recoveryBuffer,
                documentID: $0.id,
                recoveryEpoch: $0.recoveryEpoch
            )
        }

        #expect(await coordinator.saveSessionResult().persisted)

        #expect(sessions.session?.tabs.first?.encoding == latin1)
    }
}

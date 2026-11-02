import AppSettings
import CommandBridge
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
struct CommandStdinIntegrationTests {
    @MainActor private final class Store: WorkspaceSessionStoring {
        let base: WorkspaceSessionStore
        var refuses = false
        var beforeSave: ((WorkspaceSession) -> Void)?
        init(url: URL) {
            base = WorkspaceSessionStore(fileURL: url)
        }

        func loadSession() -> WorkspaceSession? {
            base.loadSession()
        }

        func saveSession(_ session: WorkspaceSession) {
            _ = saveSessionVerified(session)
        }

        func saveSessionVerified(_ session: WorkspaceSession) -> Bool {
            beforeSave?(session)
            return !refuses && base.saveSessionVerified(session)
        }
    }

    @MainActor private struct Fixture {
        let directory: URL
        let defaultsName: String
        let coordinator: WindowCoordinator
        let store: Store
        let recovery: RecoveryBuffer
        let receiver: CommandApplicationReceiver

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            defaultsName = "test.command-stdin." + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: defaultsName))
            store = Store(url: directory.appendingPathComponent("session.json"))
            recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("recovery"))
            let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
            coordinator = WindowCoordinator(
                sessionStore: store, recoveryBuffer: recovery,
                themeController: ThemeController(preferenceStore: UserDefaultsThemePreferenceStore(defaults: defaults)),
                grammarRegistry: GrammarRegistry(), fileTreePreferences: preferences,
                recentFolderRoots: RecentFolderRoots(preferences: preferences),
                recentFileDocuments: RecentFileDocuments(preferences: preferences),
                appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
                workspaceStateStore: WorkspaceStateStore(defaults: defaults)
            )
            receiver = coordinator.makeCommandReceiver()
        }

        func close() {
            store.beforeSave = nil
            coordinator.afterSessionRecoveryPersisted = nil
            (coordinator.controllers + coordinator.commandStdinStages).forEach { $0.window?.close() }
            coordinator.saveTask?.cancel()
            UserDefaults.standard.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func acknowledgementFollowsHiddenRecoveryAndCanonicalPublication() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("\u{FEFF}author\r\nlast\r".utf8)
        fixture.store.beforeSave = { session in
            #expect(fixture.coordinator.controllers.isEmpty)
            #expect(fixture.coordinator.commandStdinStages.count == 1)
            #expect(fixture.coordinator.commandStdinStages.first?.window?.isVisible == false)
            #expect(session.tabs.first?.untitledDocumentID != nil)
        }
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: bytes), wait: true)
        let mailbox = CommandReplyMailbox()
        try fixture.receiver.submit(CommandValidatedInput(request: request, bytes: bytes),
                                    subscriber: UUID(), mailbox: mailbox)
        try await wait { mailbox.snapshot?.events.isEmpty == false }
        fixture.store.beforeSave = nil
        let controller = try #require(fixture.coordinator.controllers.first)
        let document = try #require(controller.model.activeDocument)
        #expect(fixture.coordinator.commandStdinStages.isEmpty)
        #expect(document.state == .dirty)
        #expect(document.text.utf8.elementsEqual("\u{FEFF}author\r\nlast\r".utf8))
        #expect(document.encoding.bom == .utf8)
        let record = try #require(fixture.store.base.loadSession()?.tabs.first)
        #expect(record.untitledDocumentID == document.id)
        #expect(record.documentRecoveryEpoch == document.recoveryEpoch)
        #expect(record.encoding == document.encoding)
        let recovered = try #require(try await fixture.recovery.load(for: document.id, epoch: document.recoveryEpoch))
        #expect(recovered.utf8.elementsEqual(document.text.utf8))
        #expect(mailbox.snapshot?.events == [.accepted(requestID: request.id, openedCount: 1, failures: [])])

        let logicalLifetime = controller.commandDocumentLifetime
        let destination = fixture.directory.appendingPathComponent("saved.md")
        await controller.model.saveAs(to: destination, expecting: document)
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(controller.commandDocumentLifetime == logicalLifetime)
        #expect(mailbox.snapshot?.isTerminal == false)
        controller.window?.close()
        #expect(mailbox.snapshot?.isTerminal == true)
    }

    @Test func failedCanonicalPublicationNeverExposesOrAcknowledgesTheStage() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.store.refuses = true
        var captured: TabRecord?
        fixture.store.beforeSave = { captured = $0.tabs.first }
        let bytes = Data("keep authored source".utf8)
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: bytes), wait: true)
        let mailbox = CommandReplyMailbox()
        try fixture.receiver.submit(CommandValidatedInput(request: request, bytes: bytes),
                                    subscriber: UUID(), mailbox: mailbox)
        try await wait { mailbox.snapshot?.isTerminal == true }
        #expect(fixture.coordinator.controllers.isEmpty)
        #expect(fixture.coordinator.commandStdinStages.isEmpty)
        #expect(fixture.store.base.loadSession() == nil)
        #expect(mailbox.snapshot?.events == [.rejected(requestID: request.id, reason: .recoveryUnavailable)])
        let record = try #require(captured)
        let identity = try #require(record.untitledDocumentID)
        let epoch = try #require(record.documentRecoveryEpoch)
        let retained = try #require(try await fixture.recovery.load(for: identity, epoch: epoch))
        #expect(retained.utf8.elementsEqual("keep authored source".utf8))
    }

    @Test func emptyStdinIsDirtyAndRestoresThroughTheOrdinarySessionReader() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: Data()))
        let mailbox = CommandReplyMailbox()
        try fixture.receiver.submit(CommandValidatedInput(request: request, bytes: Data()),
                                    subscriber: UUID(), mailbox: mailbox)
        try await wait { mailbox.snapshot?.isTerminal == true }
        let document = try #require(fixture.coordinator.controllers.first?.model.activeDocument)
        #expect(document.state == .dirty)
        #expect(document.text.isEmpty)
        let restarted = TabStore(sessionStore: WorkspaceSessionStore(fileURL: fixture.directory
                                     .appendingPathComponent("session.json")),
        recoveryBuffer: RecoveryBuffer(recoveryDirectory: fixture.directory
            .appendingPathComponent("recovery")))
        await restarted.restoreSessionIfNeeded()
        let restored = try #require(restarted.activeTab?.document)
        #expect(restored.id == document.id)
        #expect(restored.recoveryEpoch == document.recoveryEpoch)
        #expect(restored.state == .dirty)
        #expect(restored.text.isEmpty)
    }

    @MainActor private final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pass() async {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume(); continuation = nil
        }
    }

    @Test func anOlderAutosaveCannotEraseTheAdmittedStdinReference() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let gate = Gate()
        defer { gate.release() }
        var passes = 0
        fixture.coordinator.afterSessionRecoveryPersisted = {
            passes += 1
            if passes == 1 {
                await gate.pass()
            }
        }
        let older = Task { @MainActor in await fixture.coordinator.saveSessionResult(isAutosave: true) }
        try await wait { gate.entered }
        let bytes = Data("new authored stdin".utf8)
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: bytes))
        let mailbox = CommandReplyMailbox()
        try fixture.receiver.submit(CommandValidatedInput(request: request, bytes: bytes),
                                    subscriber: UUID(), mailbox: mailbox)
        try await wait { mailbox.snapshot?.isTerminal == true }
        let document = try #require(fixture.coordinator.controllers.first?.model.activeDocument)
        gate.release()
        _ = await older.value
        let record = try #require(fixture.store.base.loadSession()?.tabs.first)
        #expect(record.untitledDocumentID == document.id)
        #expect(record.documentRecoveryEpoch == document.recoveryEpoch)
        #expect(fixture.store.base.loadSession()?.tabs.count == 1)
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

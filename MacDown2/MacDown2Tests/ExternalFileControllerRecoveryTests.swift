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

@MainActor
struct ExternalFileControllerRecoveryTests {
    @Test func anotherTabsSuccessfulRecoveryDoesNotClearAnInactiveDraftRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let first = FileDocument(fileURL: directory.appendingPathComponent("first.md"), recoveryBuffer: buffer)
            .updatingText("first draft")
        let second = FileDocument(fileURL: directory.appendingPathComponent("second.md"), recoveryBuffer: buffer)
            .updatingText("second draft")
        let store = TabStore(sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")))
        store.newTab(document: first)
        store.newTab(document: second)
        let model = WorkspaceModel(tabStore: store)
        let executor = ScriptedRecoveryExecutor()
        let controller = ExternalFileController(
            model: model, editorStore: EditorTextSystemStore(), identity: "inactive-recovery-test",
            recoveryExecutor: executor
        )
        await executor.failNext(.persist)
        controller.persistRecovery(for: first)
        await controller.drainRecovery()
        #expect(controller.recoveryRetryKind == .persist)

        controller.persistRecovery(for: second)
        await controller.drainRecovery()
        #expect(controller.recoveryRetryKind == .persist)
        controller.retryRecoveryCleanup()
        await controller.drainRecovery()
        #expect(controller.recoveryRetryKind == nil)
        #expect(try await buffer.load(for: first.id, epoch: first.recoveryEpoch) == "first draft")
        #expect(try await buffer.load(for: second.id, epoch: second.recoveryEpoch) == "second draft")
    }

    @Test func terminationFailureExposesRecoveryRequiredRetryAndSaveAsPresentation() {
        let suite = "com.joncallim.macdown2.termination-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Unable to create an isolated defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FileTreePreferences(
            store: UserDefaultsFileTreePreferenceStore(defaults: defaults)
        )
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )

        #expect(!coordinator.handleTerminationSessionResult(false))
        #expect(coordinator.terminationRecoveryState == .recoveryRequired)
        #expect(TerminationRecoveryPresentation.retryTitle == "Retry")
        #expect(TerminationRecoveryPresentation.saveAsTitle == "Save As…")
    }

    @Test func terminationSaveTargetsTheNonKeyControllerWhoseRecoveryFailed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recoveryLocation = directory.appendingPathComponent("Recovery")
        try Data("not a directory".utf8).write(to: recoveryLocation)
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryLocation)
        guard let coordinator = makeCoordinator(directory: directory, recoveryBuffer: recovery) else {
            Issue.record("Unable to create isolated defaults for the coordinator")
            return
        }
        let firstModel = coordinator.makeWindowModel()
        firstModel.newDocument()
        let secondModel = coordinator.makeWindowModel()
        secondModel.newDocument()
        secondModel.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        let first = makeWindowController(model: firstModel, coordinator: coordinator)
        let second = makeWindowController(model: secondModel, coordinator: coordinator)
        coordinator.controllers = [first, second]

        let result = await coordinator.saveSessionResult()
        guard case let .recoveryFailed(failedController) = result else {
            Issue.record("Expected the dirty non-key controller to fail session recovery publication")
            return
        }
        #expect(failedController === second)
    }

    @Test func retryRetainsAndClearsEveryTypedRecoveryAction() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = FileDocument(
            fileURL: directory.appendingPathComponent("source.md"),
            recoveryBuffer: buffer
        )
        .updatingText("source")
        let destination = FileDocument(
            fileURL: directory.appendingPathComponent("destination.md"),
            recoveryBuffer: buffer
        )
        .updatingText("destination")
        let executor = ScriptedRecoveryExecutor()
        let store = TabStore(sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")))
        store.newTab(document: destination)
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "controller-retry-test",
            recoveryExecutor: executor
        )

        await exerciseRecoveryRetries(
            controller: controller,
            executor: executor,
            buffer: buffer,
            source: source,
            destination: destination
        )

        await assertRetirementRetry(
            controller: controller,
            executor: executor,
            document: destination,
            expectedURL: recoveryURL(buffer: buffer, document: destination)
        )

        #expect(await executor.calls == [
            .persist, .persist, .remove, .remove, .migrate, .migrate, .retire, .retire,
        ])
    }

    @Test func movePreparationFailuresRetainRetryForMigrationAndRemoval() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let executor = ScriptedRecoveryExecutor()
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        let dirtySource = FileDocument(fileURL: sourceURL, recoveryBuffer: buffer).updatingText("draft")
        let store = TabStore(sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")))
        store.newTab(document: dirtySource)
        // `ExternalFileController.model` is `weak`; a real window controller
        // keeps the `WorkspaceModel` alive. Without a local `let` here the
        // model is deallocated as soon as `init` returns, so every
        // `isCurrentRecoveryAction` check below silently sees `model == nil`.
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "move-retry-test",
            recoveryExecutor: executor
        )

        await executor.failNext(.migrate)
        #expect(await !(controller.prepareMoveRecovery(from: dirtySource, to: dirtySource.renamed(to: destinationURL))))
        #expect(controller.recoveryRetryKind == .migrate)
        controller.retryRecoveryCleanup()
        await controller.drainRecovery()
        #expect(controller.recoveryRetryKind == nil)
        #expect(controller.notice == .none)

        let cleanSource = FileDocument(fileURL: sourceURL, recoveryBuffer: buffer)
        store.updateActiveDocument { _ in cleanSource }
        await executor.failNext(.remove)
        #expect(await !(controller.prepareMoveRecovery(from: cleanSource, to: cleanSource.renamed(to: destinationURL))))
        #expect(controller.recoveryRetryKind == .remove)
        controller.retryRecoveryCleanup()
        await controller.drainRecovery()
        #expect(controller.recoveryRetryKind == nil)
        #expect(controller.notice == .none)
    }

    @Test func migrationRetryResumesTheCompleteMoveAndPublishesItsReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery)
            .load()
            .updatingText("local draft")
        let sessions = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store)
        let executor = ScriptedRecoveryExecutor()
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "move-continuation-test",
            recoveryExecutor: executor
        )

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        let snapshot = try source.fileStore.readSnapshot(from: destinationURL)
        await executor.failNext(.migrate)

        await controller.applyMove(snapshot, to: source, model: model)
        #expect(model.activeDocument?.id == source.id)
        #expect(controller.recoveryRetryKind == .migrate)

        controller.retryRecoveryCleanup()
        await controller.drainRecovery()

        let moved = try #require(model.activeDocument)
        #expect(moved.fileURL == destinationURL.standardizedFileURL)
        #expect(moved.id == destinationURL.standardizedFileURL.absoluteString)
        #expect(controller.boundURL == destinationURL.standardizedFileURL)
        #expect(controller.recoveryRetryKind == nil)
        #expect(sessions.loadSession()?.tabs.first?.fileURL == destinationURL.standardizedFileURL)
        #expect(try await recovery.load(for: moved.id, epoch: moved.recoveryEpoch) == "local draft")

        let restored = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        await restored.restoreSessionIfNeeded()
        #expect(restored.activeDocument?.fileURL == destinationURL.standardizedFileURL)
        #expect(restored.activeDocument?.text == "local draft")
    }

    @Test func discardRetirementRetryCompletesCloseAndDoesNotReviveTheDiscardedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let session = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: session, recoveryBuffer: buffer)
        let document = FileDocument(text: "discard me", recoveryBuffer: buffer).updatingText("discard me")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        guard let coordinator = makeCoordinator(directory: directory, recoveryBuffer: buffer) else {
            Issue.record("Unable to create isolated coordinator")
            return
        }
        let executor = ScriptedRecoveryExecutor()
        let controller = makeWindowController(model: model, coordinator: coordinator, recoveryExecutor: executor)
        coordinator.controllers = [controller]
        await document.saveRecovery()
        await executor.failNext(.retire)

        #expect(await !(controller.externalFileController.retireRecovery(
            for: document,
            resumeCloseOnSuccess: true
        )).isAbsent)
        #expect(controller.externalFileController.recoveryRetryKind == .retire)

        controller.externalFileController.retryRecoveryCleanup()
        await controller.externalFileController.drainRecovery()

        #expect(coordinator.controllers.isEmpty)
        let relaunched = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        #expect(try await relaunched.load(for: document.id, epoch: document.recoveryEpoch) == nil)
    }
}

extension ExternalFileControllerRecoveryTests {
    private func exerciseRecoveryRetries(
        controller: ExternalFileController,
        executor: ScriptedRecoveryExecutor,
        buffer: RecoveryBuffer,
        source: FileDocument,
        destination: FileDocument
    ) async {
        let destinationRecoveryURL = await recoveryURL(buffer: buffer, document: destination)
        let sourceRecoveryURL = await buffer.recoveryLocation(for: source.id, epoch: source.recoveryEpoch)
        await assertRetry(
            kind: .persist,
            controller: controller,
            executor: executor,
            expectedURL: destinationRecoveryURL
        ) {
            controller.persistRecovery(for: destination)
        }
        await assertRetry(
            kind: .remove,
            controller: controller,
            executor: executor,
            expectedURL: destinationRecoveryURL
        ) {
            controller.removeRecovery(for: destination)
        }
        await assertRetry(
            kind: .migrate,
            controller: controller,
            executor: executor,
            expectedURL: sourceRecoveryURL
        ) {
            controller.migrateRecovery(from: source.id, sourceEpoch: source.recoveryEpoch, to: destination)
        }
    }

    private func assertRetirementRetry(
        controller: ExternalFileController,
        executor: ScriptedRecoveryExecutor,
        document: FileDocument,
        expectedURL: URL
    ) async {
        await executor.failNext(.retire)
        #expect(await !(controller.retireRecovery(for: document)).isAbsent)
        #expect(controller.recoveryRetryKind == .retire)
        #expect(controller.notice == .recoveryCleanup(expectedURL))

        controller.retryRecoveryCleanup()
        await controller.drainRecovery()

        #expect(controller.recoveryRetryKind == nil)
        #expect(controller.notice == .none)
    }

    private func recoveryURL(buffer: RecoveryBuffer, document: FileDocument) async -> URL {
        await buffer.recoveryLocation(for: document.id, epoch: document.recoveryEpoch)
    }

    func makeCoordinator(directory: URL, recoveryBuffer: RecoveryBuffer) -> WindowCoordinator? {
        let suite = "com.joncallim.macdown2.recovery-target.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        return WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")),
            recoveryBuffer: recoveryBuffer,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences(
                store: UserDefaultsFileTreePreferenceStore(defaults: defaults)
            ),
            recentFolderRoots: RecentFolderRoots(preferences: FileTreePreferences(
                store: UserDefaultsFileTreePreferenceStore(defaults: defaults)
            )),
            recentFileDocuments: RecentFileDocuments(preferences: FileTreePreferences(
                store: UserDefaultsFileTreePreferenceStore(defaults: defaults)
            )),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
    }

    func makeWindowController(
        model: WorkspaceModel,
        coordinator: WindowCoordinator,
        recoveryExecutor: any RecoveryActionExecuting = DefaultRecoveryActionExecutor()
    ) -> WindowController {
        WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences(),
            recoveryExecutor: recoveryExecutor
        )
    }

    private func assertRetry(
        kind: ExternalFileController.RecoveryRetryKind,
        controller: ExternalFileController,
        executor: ScriptedRecoveryExecutor,
        expectedURL: URL,
        perform: @MainActor () -> Void
    ) async {
        await executor.failNext(kind)
        perform()
        await controller.drainRecovery()

        #expect(controller.recoveryRetryKind == kind)
        #expect(controller.notice == .recoveryCleanup(expectedURL))

        controller.retryRecoveryCleanup()
        await controller.drainRecovery()

        #expect(controller.recoveryRetryKind == nil)
        #expect(controller.notice == .none)
    }
}

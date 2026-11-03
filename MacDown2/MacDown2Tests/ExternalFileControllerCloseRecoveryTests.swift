import AppKit
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
struct ExternalFileControllerCloseRecoveryTests {
    @MainActor
    private final class TerminationPresentationProbe {
        var requests = 0
        var window: NSWindow?
        var target: WindowController?

        func record(window: NSWindow, target: WindowController?) {
            requests += 1
            self.window = window
            self.target = target
        }
    }

    @Test func retryAfterAnEditKeepsTheWindowOpenWithAFreshPersistedLifetime() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: buffer
        )
        let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        let helpers = ExternalFileControllerRecoveryTests()
        guard let coordinator = helpers.makeCoordinator(directory: directory, recoveryBuffer: buffer) else {
            Issue.record("Unable to create isolated coordinator")
            return
        }
        let executor = ScriptedRecoveryExecutor()
        let controller = helpers.makeWindowController(
            model: model,
            coordinator: coordinator,
            recoveryExecutor: executor
        )
        coordinator.controllers = [controller]
        await document.saveRecovery()
        await executor.failNext(.retire)

        #expect(await !(controller.externalFileController.retireRecovery(
            for: document,
            resumeCloseOnSuccess: true
        )).isAbsent)
        model.tabStore.updateActiveDocument { $0.updatingText("later edit") }

        controller.externalFileController.retryRecoveryCleanup()
        await controller.externalFileController.drainRecovery()

        let current = try #require(model.activeDocument)
        #expect(coordinator.controllers.contains { $0 === controller })
        #expect(current.recoveryEpoch != document.recoveryEpoch)
        let relaunched = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        #expect(try await relaunched.load(for: current.id, epoch: current.recoveryEpoch) == "later edit")
    }

    @Test func failedFreshLifetimePersistenceRetainsRetryAndRestoresEditedText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let session = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: session, recoveryBuffer: buffer)
        let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        let helpers = ExternalFileControllerRecoveryTests()
        guard let coordinator = helpers.makeCoordinator(directory: directory, recoveryBuffer: buffer) else {
            Issue.record("Unable to create isolated coordinator")
            return
        }
        let executor = FailOnceClosePreservationExecutor()
        let controller = helpers.makeWindowController(
            model: model,
            coordinator: coordinator,
            recoveryExecutor: executor
        )
        coordinator.controllers = [controller]

        #expect(await document.persistRecovery())
        await executor.failNext(.retire)
        #expect(await !(controller.externalFileController.retireRecovery(
            for: document,
            resumeCloseOnSuccess: true
        )).isAbsent)

        let edited = document.updatingText("edited before close retry")
        store.updateActiveDocument { _ in edited }
        await executor.failNext(.persist)

        controller.externalFileController.retryRecoveryCleanup()
        await controller.externalFileController.drainRecovery()

        let fresh = try #require(model.activeDocument)
        #expect(fresh.id == edited.id)
        #expect(fresh.text == edited.text)
        #expect(fresh.recoveryEpoch != document.recoveryEpoch)
        #expect(controller.externalFileController.recoveryRetryKind == .persist)

        controller.externalFileController.retryRecoveryCleanup()
        await controller.externalFileController.drainRecovery()

        #expect(controller.externalFileController.recoveryRetryKind == nil)
        #expect(controller.externalFileController.notice == .none)
        #expect(await store.saveSession())

        let relaunched = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let restored = TabStore(sessionStore: session, recoveryBuffer: relaunched)
        await restored.restoreSessionIfNeeded()
        #expect(restored.activeDocument?.recoveryEpoch == fresh.recoveryEpoch)
        #expect(restored.activeDocument?.text == edited.text)
    }

    /// Issue #168. The window's debounced session save writes the same dirty
    /// snapshot (same document, version and lifetime) that a pending persist
    /// retry is about to write. The buffer refuses to re-apply a version it
    /// has already recorded, so the retry must accept the already-secured
    /// snapshot rather than re-arm itself and keep the cleanup notice forever.
    /// The session save is forced between the failure and the retry here;
    /// on CI it happened there by timing.
    @Test func persistRetryAcceptsASnapshotTheSessionSaveAlreadySecured() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let session = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: session, recoveryBuffer: buffer)
        let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        let helpers = ExternalFileControllerRecoveryTests()
        guard let coordinator = helpers.makeCoordinator(directory: directory, recoveryBuffer: buffer) else {
            Issue.record("Unable to create isolated coordinator")
            return
        }
        let executor = FailOnceClosePreservationExecutor()
        let controller = helpers.makeWindowController(
            model: model,
            coordinator: coordinator,
            recoveryExecutor: executor
        )
        coordinator.controllers = [controller]

        #expect(await document.persistRecovery())
        await executor.failNext(.retire)
        #expect(await !(controller.externalFileController.retireRecovery(
            for: document,
            resumeCloseOnSuccess: true
        )).isAbsent)
        store.updateActiveDocument { _ in document.updatingText("edited before close retry") }
        await executor.failNext(.persist)
        controller.externalFileController.retryRecoveryCleanup()
        await controller.externalFileController.drainRecovery()
        #expect(controller.externalFileController.recoveryRetryKind == .persist)
        let fresh = try #require(model.activeDocument)

        #expect(await coordinator.saveSession())

        controller.externalFileController.retryRecoveryCleanup()
        await controller.externalFileController.drainRecovery()

        #expect(controller.externalFileController.recoveryRetryKind == nil)
        #expect(controller.externalFileController.notice == .none)
        let relaunched = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        #expect(try await relaunched.load(for: fresh.id, epoch: fresh.recoveryEpoch) == fresh.text)
    }

    @Test func nativeCloseRefusesAWindowWithPendingWorkspaceRecoveryCleanup() async throws {
        let fixture = try await pendingCleanupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let helpers = ExternalFileControllerRecoveryTests()
        guard let coordinator = helpers.makeCoordinator(
            directory: fixture.directory,
            recoveryBuffer: fixture.recovery
        ) else {
            Issue.record("Unable to create isolated coordinator")
            return
        }
        let controller = helpers.makeWindowController(model: fixture.model, coordinator: coordinator)
        coordinator.controllers = [controller]
        let window = try #require(controller.window)

        #expect(fixture.model.hasPendingRecoveryCleanup)
        #expect(!controller.windowShouldClose(window))
        #expect(coordinator.controllers.contains { $0 === controller })
        #expect(fixture.model.activeDocument != nil)
    }

    @Test func terminationBlocksPendingCleanupAndKeepsTheLastPublishedSessionRecoverable() async throws {
        let fixture = try await pendingCleanupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let helpers = ExternalFileControllerRecoveryTests()
        guard let coordinator = helpers.makeCoordinator(
            directory: fixture.directory,
            recoveryBuffer: fixture.recovery
        ) else {
            Issue.record("Unable to create isolated coordinator")
            return
        }
        let controller = helpers.makeWindowController(model: fixture.model, coordinator: coordinator)
        coordinator.controllers = [controller]

        let result = await coordinator.saveSessionResult()
        guard case let .pendingRecoveryCleanup(blockingController) = result else {
            Issue.record("Expected pending recovery cleanup to block termination")
            return
        }
        #expect(blockingController === controller)
        let presentation = TerminationPresentationProbe()
        coordinator.terminationRecoveryAlertPresenter = { window, target in
            presentation.record(window: window, target: target)
        }
        defer { coordinator.terminationRecoveryAlertPresenter = nil }
        #expect(!coordinator.handleTerminationSessionResult(result))
        #expect(coordinator.terminationRecoveryState == .recoveryRequired)
        #expect(coordinator.terminationRecoveryController === controller)
        #expect(presentation.requests == 1)
        #expect(presentation.window === controller.window)
        #expect(presentation.target === controller)
        #expect(controller.window?.attachedSheet == nil)

        let relaunched = TabStore(
            sessionStore: fixture.session,
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: fixture.recoveryDirectory)
        )
        await relaunched.restoreSessionIfNeeded()
        #expect(relaunched.activeDocument?.text == "draft")
    }

    private func pendingCleanupFixture() async throws -> PendingCleanupFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        try Data("not a directory".utf8).write(to: recoveryDirectory)
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        let fileURL = directory.appendingPathComponent("notes.md")
        try "disk".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = try FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load().updatingText("draft")
        let session = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session"))
        let store = TabStore(sessionStore: session, recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        await model.save()
        #expect(model.hasPendingRecoveryCleanup)
        // `TabStore.updateActiveDocument` only schedules a 300ms-debounced
        // session save; publish synchronously so callers that assert on the
        // "last published session" right after this fixture returns don't
        // race that background timer.
        #expect(await store.saveSession())
        return PendingCleanupFixture(
            directory: directory,
            recoveryDirectory: recoveryDirectory,
            recovery: recovery,
            session: session,
            model: model
        )
    }
}

private struct PendingCleanupFixture {
    let directory: URL
    let recoveryDirectory: URL
    let recovery: RecoveryBuffer
    let session: WorkspaceSessionStore
    let model: WorkspaceModel
}

actor FailOnceClosePreservationExecutor: RecoveryActionExecuting {
    private var failures: Set<ExternalFileController.RecoveryRetryKind> = []

    func failNext(_ kind: ExternalFileController.RecoveryRetryKind) {
        failures.insert(kind)
    }

    func persist(_ document: FileDocument) async -> Bool {
        guard failures.remove(.persist) == nil else { return false }
        return await document.persistRecovery()
    }

    func remove(
        _ buffer: RecoveryBuffer,
        id: String,
        version: UInt,
        epoch: UUID
    ) async -> RecoveryCleanupResult {
        await buffer.removeWithOutcome(for: id, version: version, epoch: epoch)
    }

    func migrate(
        _ buffer: RecoveryBuffer,
        oldID: String,
        sourceEpoch: UUID,
        document: FileDocument
    ) async -> RecoveryMigrationOutcome {
        await buffer.migrateWithOutcome(
            from: oldID,
            to: document.id,
            content: document.text,
            version: document.mutationGeneration,
            sourceEpoch: sourceEpoch,
            destinationEpoch: document.recoveryEpoch
        )
    }

    func retire(_ buffer: RecoveryBuffer, id: String, epoch: UUID) async -> RecoveryCleanupResult {
        guard failures.remove(.retire) == nil else {
            return .failed(.removalFailed(URL(fileURLWithPath: id), 5))
        }
        return await buffer.retireWithOutcome(for: id, epoch: epoch)
    }
}

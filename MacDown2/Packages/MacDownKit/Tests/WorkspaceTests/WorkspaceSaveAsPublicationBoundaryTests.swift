@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Test func dirtySaveAsKeepsRedirectUntilItsCanonicalSessionIsVerified() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let sourceURL = directory.appendingPathComponent("source.md")
    let destinationURL = directory.appendingPathComponent("destination.md")
    try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)

    let recoveryDirectory = directory.appendingPathComponent("Recovery")
    let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
    let barrier = SaveAsBoundaryBarrier()
    let fileStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
    let initial = try await FileDocument.create(
        fileURL: sourceURL,
        fileStore: fileStore,
        recoveryBuffer: recovery
    )
    let source = try initial.load().updatingText("draft")
    #expect(await source.persistRecovery())

    let local = NonPublishingSessionStore()
    let canonical = FakeSessionStore()
    let store = TabStore(sessionStore: local, recoveryBuffer: recovery)
    store.newTab(document: source)
    canonical.saveSession(store.currentSession())

    let panel = FakeFilePanelProvider()
    panel.nextSaveURL = destinationURL
    let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)
    let probe = SaveAsPublicationProbe()
    model.setSaveAsSessionPublisher {
        canonical.saveSessionVerified(store.currentSession())
    }
    model.onSaveAsDestinationSessionPublished = { source, _ in
        #expect(model.isSavingActiveDocument, "migration acknowledgement still belongs to Save As")
        probe.publishedSession = canonical.loadSession()
        let relaunched = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        probe.sourceRedirectText = try? await relaunched.load(for: source.id, epoch: source.recoveryEpoch)
    }

    let saveAs = Task { @MainActor in await model.saveAs() }
    #expect(await barrier.waitForPublication())
    model.tabStore.updateActiveDocument { $0.updatingText("edited during Save As") }
    barrier.allowPublication()
    await saveAs.value

    #expect(probe.publishedSession?.tabs.first?.fileURL == destinationURL.standardizedFileURL)
    #expect(probe.sourceRedirectText == "edited during Save As")

    let relaunchedRecovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
    #expect(try await relaunchedRecovery.load(for: source.id, epoch: source.recoveryEpoch) == nil)
    let restored = TabStore(sessionStore: canonical, recoveryBuffer: relaunchedRecovery)
    await restored.restoreSessionIfNeeded()
    #expect(restored.activeDocument?.fileURL == destinationURL.standardizedFileURL)
    #expect(restored.activeDocument?.text == "edited during Save As")
}

@MainActor
private final class NonPublishingSessionStore: WorkspaceSessionStoring {
    func loadSession() -> WorkspaceSession? {
        nil
    }

    func saveSession(_: WorkspaceSession) {}
}

@MainActor
private final class SaveAsPublicationProbe {
    var publishedSession: WorkspaceSession?
    var sourceRedirectText: String?
}

private final class SaveAsBoundaryBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var arrived = false
    private var waiter: CheckedContinuation<Bool, Never>?

    func arriveAndWait() {
        lock.lock()
        arrived = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(returning: true)
        _ = semaphore.wait(timeout: .now() + 3)
    }

    func waitForPublication() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if arrived {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func allowPublication() {
        semaphore.signal()
    }
}

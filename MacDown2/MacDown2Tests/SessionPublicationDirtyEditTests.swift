import FileCore
import Foundation
@testable import MacDown2
import Testing

extension SessionViewStateRoundTripTests {
    @Test func dirtyEditDuringRecoveryCannotPublishAnOlderTerminationSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        await coordinator.awaitScheduledSessionSaveForTesting()
        controller.model.tabStore.updateActiveDocument { $0.edited(text: "first edit") }
        controller.updateTitleAndEditedState()
        await coordinator.awaitScheduledSessionSaveForTesting()
        #expect(sessions.publicationCount > 0)
        sessions.session = nil
        sessions.publicationCount = 0
        let firstDocument = try #require(controller.model.activeDocument)
        let (firstGate, secondGate) = (FirstCallGate(), FirstCallGate())
        var rejectedSnapshots: [(superseded: Bool, documentChanged: Bool)] = []
        coordinator.afterSessionPublicationRejected = { superseded, documentChanged in
            rejectedSnapshots.append((superseded, documentChanged))
        }
        defer { [firstGate, secondGate].forEach { $0.release() } }
        var recoveryPasses = 0
        coordinator.afterSessionRecoveryPersisted = {
            recoveryPasses += 1
            if recoveryPasses == 1 {
                await firstGate.pass()
            } else if recoveryPasses == 2 {
                await secondGate.pass()
            }
        }

        let termination = Task { @MainActor in await coordinator.saveSessionForTermination() }
        for _ in 0 ..< 1000 where !firstGate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(firstGate.entered)

        // This is the ordinary editor-binding path: dirty -> dirty does not schedule a coordinator session save.
        controller.model.tabStore.updateActiveDocument { $0.edited(text: "second edit") }
        let currentDocument = try #require(controller.model.activeDocument)
        #expect(currentDocument.mutationGeneration > firstDocument.mutationGeneration)
        firstGate.release()
        for _ in 0 ..< 1000 where !secondGate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(secondGate.entered)

        #expect(sessions.publicationCount == 0)
        let recovered = try await currentDocument.recoveryBuffer.load(
            for: currentDocument.id, epoch: currentDocument.recoveryEpoch
        )
        #expect(recovered?.isExactlyEqual(to: "second edit") == true)
        secondGate.release()

        #expect(await termination.value.persisted, "Publication rejections: \(rejectedSnapshots)")
        #expect(sessions.publicationCount == 1)
        #expect(sessions.session?.tabs.first?.documentRecoveryEpoch == currentDocument.recoveryEpoch)
    }

    @Test func terminationOwnsTheSessionLaneWhenAnotherSaveIsScheduled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        await coordinator.awaitScheduledSessionSaveForTesting()
        sessions.session = nil
        sessions.publicationCount = 0

        var explicitRecoveryPasses = 0
        coordinator.afterSessionRecoveryPersisted = {
            explicitRecoveryPasses += 1
            if explicitRecoveryPasses == 1 {
                coordinator.scheduleSaveSession()
            }
        }

        let result = await coordinator.saveSessionForTermination()
        await coordinator.awaitScheduledSessionSaveForTesting()

        #expect(result.persisted)
        #expect(explicitRecoveryPasses == 2)
        let currentDocument = try #require(coordinator.controllers.first?.model.activeDocument)
        #expect(sessions.session?.tabs.first?.documentRecoveryEpoch == currentDocument.recoveryEpoch)
    }

    @Test func terminationDrainsAnAutosaveBeforeLaunchRestoreCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        await coordinator.awaitScheduledSessionSaveForTesting()
        sessions.session = nil
        sessions.publicationCount = 0

        let autosaveGate = FirstCallGate()
        let restoreGate = FirstCallGate()
        defer {
            autosaveGate.release()
            restoreGate.release()
        }
        var recoveryPasses = 0
        var autosaveResumed = false
        var autosaveWasCancelledOnResume = false
        coordinator.afterSessionRecoveryPersisted = {
            recoveryPasses += 1
            if recoveryPasses == 1 {
                await autosaveGate.pass()
                autosaveWasCancelledOnResume = Task.isCancelled
                autosaveResumed = true
            }
        }

        coordinator.restoreTask = Task { @MainActor in await restoreGate.pass() }
        try await waitForCondition { restoreGate.entered }

        coordinator.scheduleSaveSession()
        try await waitForCondition { autosaveGate.entered }

        let termination = Task { @MainActor in await coordinator.saveSessionForTermination() }
        try await waitForCondition { coordinator.terminationSaveInProgress }
        autosaveGate.release()
        try await waitForCondition { autosaveResumed }

        #expect(autosaveWasCancelledOnResume)
        #expect(sessions.publicationCount == 0)
        restoreGate.release()

        let result = await termination.value

        #expect(result.persisted)
        #expect(recoveryPasses == 2)
        #expect(sessions.publicationCount == 1)
        let currentDocument = try #require(coordinator.controllers.first?.model.activeDocument)
        #expect(sessions.session?.tabs.first?.documentRecoveryEpoch == currentDocument.recoveryEpoch)
    }

    private func waitForCondition(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 1000 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

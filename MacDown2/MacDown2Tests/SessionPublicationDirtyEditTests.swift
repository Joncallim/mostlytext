import FileCore
import Foundation
@testable import MacDown2
import Testing

extension SessionViewStateRoundTripTests {
    @Test(arguments: [false, true])
    func dirtyEditDuringRecoveryCannotPublishAnOlderTerminationSnapshot(injectBaselineObservation: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        try await settleInitialMonitoring(of: coordinator)
        let baselineSnapshot = try baselineSnapshot(of: controller)
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
        try await waitForCondition { firstGate.entered }

        // This is the ordinary editor-binding path: dirty -> dirty does not schedule a coordinator session save.
        controller.model.tabStore.updateActiveDocument { $0.edited(text: "second edit") }
        let currentDocument = try #require(controller.model.activeDocument)
        #expect(currentDocument.mutationGeneration > firstDocument.mutationGeneration)
        firstGate.release()
        try await waitForCondition { secondGate.entered }

        #expect(sessions.publicationCount == 0)
        let recovered = try await currentDocument.recoveryBuffer.load(
            for: currentDocument.id, epoch: currentDocument.recoveryEpoch
        )
        #expect(recovered?.isExactlyEqual(to: "second edit") == true)
        if injectBaselineObservation {
            try await applyBaselineObservation(baselineSnapshot, to: controller, expecting: currentDocument)
        }
        secondGate.release()

        let result = await termination.value
        expectPublication(result, sessions, currentDocument, rejectedSnapshots, injectBaselineObservation)
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

    private func baselineSnapshot(of controller: WindowController) throws -> FileSnapshot {
        let baseline = try #require(controller.model.activeDocument)
        return try FileSnapshot(
            text: baseline.text, encoding: baseline.encoding.encoding, bom: baseline.encoding.bom,
            revision: #require(baseline.lastKnownRevision)
        )
    }

    private func applyBaselineObservation(
        _ snapshot: FileSnapshot, to controller: WindowController, expecting document: FileDocument
    ) async throws {
        // The unchanged disk baseline still advances dirty-document metadata.
        controller.externalFileController.handle(.available(snapshot))
        try await waitForCondition {
            controller.model.activeDocument?.mutationGeneration != document.mutationGeneration
        }
        let observed = try #require(controller.model.activeDocument)
        #expect(observed.id == document.id)
        #expect(observed.recoveryEpoch == document.recoveryEpoch)
        #expect(observed.text.isExactlyEqual(to: "second edit"))
        #expect(observed.mutationGeneration > document.mutationGeneration)
    }

    private func expectPublication(
        _ result: SessionSaveResult, _ sessions: MemorySessionStore, _ currentDocument: FileDocument,
        _ rejectedSnapshots: [(superseded: Bool, documentChanged: Bool)], _ injectBaselineObservation: Bool
    ) {
        if injectBaselineObservation {
            #expect(!result.persisted)
            #expect(sessions.publicationCount == 0)
            #expect(sessions.session == nil)
            #expect(rejectedSnapshots.contains { $0.superseded && $0.documentChanged })
        } else {
            #expect(result.persisted, "Publication rejections: \(rejectedSnapshots)")
            #expect(sessions.publicationCount == 1)
            #expect(sessions.session?.tabs.first?.documentRecoveryEpoch == currentDocument.recoveryEpoch)
        }
    }

    private func waitForCondition(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 1000 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

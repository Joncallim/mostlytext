@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceModel save retry progress")
struct WorkspaceModelSaveRetryIndicatorTests {
    @Test func aMetadataConflictRetryKeepsOneLogicalSaveOperation() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try FileStore().write("baseline", to: url)
        let barrier = SavePublicationBarrier()
        barrier.holdSecondPublication()
        defer { barrier.cancelAndAllowPublication() }
        let heldStore = FileStore(afterBaselineVerification: { _ in
            if barrier.hasArrived {
                barrier.secondSaveEnteredWriterLane()
            } else {
                barrier.arriveAndWait()
            }
        })
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = try FileDocument(fileURL: url, fileStore: heldStore, recoveryBuffer: recovery)
            .load().edited(text: "local edit")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        let save = Task { await model.save() }
        guard await firstPublicationArrived(barrier) else {
            await save.value
            Issue.record("The first save did not reach publication")
            return
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)],
            ofItemAtPath: url.path
        )
        barrier.allowPublication()
        guard await retryEnteredWriterLane(barrier) else {
            await save.value
            Issue.record("The metadata conflict did not reach its retry")
            return
        }

        #expect(model.isSavingActiveDocument)
        #expect(model.activeSaveOperations.count == 1, "the retry is one logical user save")
        barrier.allowSecondPublication()
        await save.value
        #expect(model.activeSaveOperations.isEmpty)
        #expect(!model.isSavingActiveDocument)
        #expect(try FileStore().read(from: url).content == "local edit")
    }

    @Test func aRetryRequiringADestinationStopsSaveProgressBeforeReportingThePicker() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = FileDocument(recoveryBuffer: recovery).updatingText("local edit")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let operation = model.beginSavingIndicator(for: document)

        let result = await model.saveAttempt(
            isRetry: true,
            destinationPolicy: .reportRequirement,
            encodingOverride: nil,
            target: document,
            continuingOperation: operation
        )

        #expect(result == .requiresDestination)
        #expect(!model.isSavingActiveDocument)
        #expect(model.activeSaveOperations.isEmpty)
    }

    private func firstPublicationArrived(_ barrier: SavePublicationBarrier) async -> Bool {
        await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        )
    }

    private func retryEnteredWriterLane(_ barrier: SavePublicationBarrier) async -> Bool {
        await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForSecondSaveToEnterWriterLane() },
            onTimeout: { barrier.cancelWaiters() }
        )
    }
}

@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// `isSavingActiveDocument` (#57) is what the window's header bar reads to
/// show a "Saving…" spinner — before this there was no signal at all, so a
/// save that took a moment looked identical to the app being hung. As with
/// `isCreatingDocument` (`WorkspaceModelCreatingDocumentTests.swift`), the
/// real risk is the flag getting stuck `true` on a failure exit; every
/// branch `save()`/`saveAs()` can take is covered here.
@MainActor
@Suite("WorkspaceModel isSavingActiveDocument")
struct WorkspaceModelSavingIndicatorTests {
    @Test func clearsAfterAnOrdinarySuccessfulSave() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try FileStore().write("original", to: url)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = try FileDocument(fileURL: url, recoveryBuffer: recovery).load().updatingText("edited")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        #expect(!model.isSavingActiveDocument)
        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func clearsAfterAFailedSave() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("original", to: url)
        var attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        attributes?[FileAttributeKey.posixPermissions] = 0o555
        try? FileManager.default.setAttributes(attributes ?? [:], ofItemAtPath: directory.path)
        defer {
            var reset = try? FileManager.default.attributesOfItem(atPath: directory.path)
            reset?[FileAttributeKey.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(reset ?? [:], ofItemAtPath: directory.path)
        }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = FileDocument(fileURL: url, recoveryBuffer: recovery).updatingText("edited")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        await model.save()

        #expect(model.activeDocument?.state == .dirty)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func clearsAfterASuccessfulSaveAs() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let destination = directory.appendingPathComponent("destination.md")
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destination
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let document = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        #expect(!model.isSavingActiveDocument)
        await model.saveAs()

        #expect(model.activeDocument?.state == .clean)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func clearsAfterAFailedSaveAs() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        var attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        attributes?[FileAttributeKey.posixPermissions] = 0o555
        try? FileManager.default.setAttributes(attributes ?? [:], ofItemAtPath: directory.path)
        defer {
            var reset = try? FileManager.default.attributesOfItem(atPath: directory.path)
            reset?[FileAttributeKey.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(reset ?? [:], ofItemAtPath: directory.path)
        }
        let destination = directory.appendingPathComponent("destination.md")
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destination
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let document = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(model.activeDocument?.state != .clean)
        if case .saveFailed = model.lastError {
        } else {
            Issue.record("Expected .saveFailed, got \(String(describing: model.lastError))")
        }
        #expect(!model.isSavingActiveDocument)
    }

    @Test func saveAsRemainsBusyAfterDestinationIdentityPublishes() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let destination = directory.appendingPathComponent("destination.md")
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let source = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        var observedPublication = false
        model.setSaveAsSessionPublisher {
            observedPublication = true
            #expect(model.activeDocument?.id != source.id)
            #expect(model.isSavingActiveDocument, "the destination session is still being published")
            if let active = model.activeDocument {
                #expect(
                    model.reserveSaveAs(for: active) == nil,
                    "a second picker cannot publish during identity transfer"
                )
            }
            return true
        }

        await model.saveAs(to: destination, expecting: source)

        #expect(observedPublication)
        #expect(!model.isSavingActiveDocument)
        if let active = model.activeDocument {
            let nextAdmission = model.reserveSaveAs(for: active)
            #expect(nextAdmission != nil, "the next Save As can begin after the first one completes")
            if let nextAdmission {
                model.finishSaveAs(nextAdmission)
            }
        }
    }

    @Test func saveAsFailureAfterDestinationPublicationStopsProgressAndKeepsRecoveryVisible() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let destination = directory.appendingPathComponent("destination.md")
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let source = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        model.setSaveAsSessionPublisher {
            #expect(model.isSavingActiveDocument)
            return false
        }

        await model.saveAs(to: destination, expecting: source)

        #expect(model.activeDocument?.id != source.id)
        #expect(!model.isSavingActiveDocument)
        #expect(model.hasPendingRecoveryCleanup)
        if case .recoveryCleanupRequired = model.lastError {
        } else {
            Issue.record("Expected recovery-required state after failed destination session publication")
        }
    }

    @Test func anOverlappingSaveAsCannotPublishASecondDestinationForTheSameLifetime() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let sourceURL = directory.appendingPathComponent("source.md")
        let firstDestination = directory.appendingPathComponent("first.md")
        let secondDestination = directory.appendingPathComponent("second.md")
        _ = try FileStore().write("original", to: sourceURL)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery)
            .load().updatingText("saved text")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        model.onSaveAsRecoveryFinalized = {
            #expect(model.isSavingActiveDocument)
            model.onSaveAsRecoveryFinalized = nil
            await model.saveAs(to: secondDestination, expecting: source)
        }
        await model.saveAs(to: firstDestination, expecting: source)

        #expect(!FileManager.default.fileExists(atPath: secondDestination.path))
        #expect(try FileStore().read(from: firstDestination).content == "saved text")
        #expect(model.activeDocument?.fileURL == firstDestination.standardizedFileURL)
        #expect(!model.isSavingActiveDocument)
    }

    /// Adversarial-review finding: `save(isRetry:destinationPolicy:)` has no
    /// reentrancy guard against a second concurrent `save()` for the same
    /// document (only `inFlightSaveAsByDocumentID` blocks an overlapping
    /// *Save As*), and `reconcileSaveConflict` recurses into a nested
    /// `save(isRetry: true, ...)` call for the same document while the outer
    /// call is still unwinding. A plain `Set`-backed indicator would let
    /// whichever overlapping save finishes first clear the flag while the
    /// other is still genuinely writing — resurfacing the "looks hung"
    /// problem this feature exists to solve. This drives the reference
    /// counting directly rather than through the full async save pipeline
    /// (whose own generation/lineage reconciliation for two divergent
    /// concurrent saves is separately covered by `DocumentWriter queued
    /// saves`); `beginSavingIndicator`/`endSavingIndicator` are `internal`
    /// and reachable here via `@testable import Workspace`.
    @Test func indicatorStaysTrueWhileASecondOverlappingSaveOfTheSameDocumentIsStillInFlight() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let document = FileDocument(recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        let first = model.beginSavingIndicator(for: document)
        #expect(model.isSavingActiveDocument)

        let second = model.beginSavingIndicator(for: document)
        #expect(model.isSavingActiveDocument)

        model.endSavingIndicator(first)
        #expect(model.isSavingActiveDocument, "the second overlapping save hasn't finished yet")

        model.endSavingIndicator(second)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func aRetiredSaveCannotClearANewerOperationAfterIdentityTransfer() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let source = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let first = model.beginSavingIndicator(for: source)
        let destination = source.renamed(to: directory.appendingPathComponent("destination.md"))

        model.includeSavingLifetime(destination, in: first)
        store.updateActiveDocument { _ in destination }
        #expect(model.isSavingActiveDocument)

        let second = model.beginSavingIndicator(for: destination)
        model.endSavingIndicator(first)
        #expect(model.isSavingActiveDocument, "the later save still owns this destination")
        model.endSavingIndicator(second)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func anUnrelatedRecoveryEpochDoesNotInheritAnOlderSpinner() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let source = FileDocument(recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let operation = model.beginSavingIndicator(for: source)
        let newerLifetime = source.withFreshRecoveryLifetime()

        store.updateActiveDocument { _ in newerLifetime }
        #expect(!model.isSavingActiveDocument)
        model.includeSavingLifetime(newerLifetime, in: operation)
        #expect(model.isSavingActiveDocument)
        model.endSavingIndicator(operation)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func oneWindowFinishingCannotClearAnotherWindowsProgress() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let firstStore = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let secondStore = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let firstDocument = FileDocument(recoveryBuffer: recovery)
        let secondDocument = FileDocument(recoveryBuffer: recovery)
        firstStore.newTab(document: firstDocument)
        secondStore.newTab(document: secondDocument)
        let firstModel = WorkspaceModel(tabStore: firstStore, stateStore: FakeStateStore())
        let secondModel = WorkspaceModel(tabStore: secondStore, stateStore: FakeStateStore())
        let first = firstModel.beginSavingIndicator(for: firstDocument)
        let second = secondModel.beginSavingIndicator(for: secondDocument)

        firstModel.endSavingIndicator(first)
        #expect(!firstModel.isSavingActiveDocument)
        #expect(secondModel.isSavingActiveDocument)
        secondModel.endSavingIndicator(second)
        #expect(!secondModel.isSavingActiveDocument)
    }
}

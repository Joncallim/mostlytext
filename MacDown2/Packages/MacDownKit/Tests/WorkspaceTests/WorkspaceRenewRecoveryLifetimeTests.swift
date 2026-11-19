@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Round-4 review (b17bcf15) P2: `renewRecoveryLifetime` checked the document was current BEFORE awaiting the
/// persist and then published the older renewed copy unconditionally, reverting keystrokes typed during the await
/// (54 of 60 yield offsets); an edit during the epoch mint left the window on the retired lifetime (5 of 60).
@MainActor
struct WorkspaceRenewRecoveryLifetimeTests {
    @Test(arguments: [true, false])
    func aTabSwitchCannotLeaveAnOpenDocumentOnItsRetiredRecoveryLifetime(viaRenew: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("tabs.json")),
            recoveryBuffer: buffer
        )
        let draft = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("typed before close")
        store.newTab(document: draft)
        let draftTabID = try #require(store.activeTabID)
        store.newTab(document: FileDocument(text: "other tab", recoveryBuffer: buffer))
        let otherTabID = try #require(store.activeTabID)
        store.activate(draftTabID)
        let model = WorkspaceModel(tabStore: store)
        let cleanup = await buffer.retireWithOutcome(for: draft.id, epoch: draft.recoveryEpoch)
        #expect(cleanup.isAbsent)

        let renewal = Task { @MainActor in
            if viaRenew {
                await model.renewRecoveryLifetime(retiredFrom: draft)
            } else {
                await model.preserveOpenDocumentAfterFailedCloseRetirement(draft)
            }
        }
        // The ownership decision must follow the closing tab even when a
        // native tab switch occurs before the recovery actor returns.
        store.activate(otherTabID)
        await renewal.value

        let retained = try #require(store.tabs.first(where: { $0.id == draftTabID })?.document)
        #expect(store.activeTabID == otherTabID)
        #expect(store.activeDocument?.text == "other tab")
        #expect(retained.text == "typed before close")
        #expect(retained.recoveryEpoch != draft.recoveryEpoch)
        #expect(try await buffer.load(for: retained.id, epoch: retained.recoveryEpoch) == retained.text)
    }

    @Test func anEditAtAnyPointDuringTheRenewIsKeptAndTheLifetimeIsRenewed() async throws {
        var reverted: [Int] = []
        var notRenewed: [Int] = []
        for yields in 0 ..< 60 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let store = TabStore(
                sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("tabs.json")),
                recoveryBuffer: buffer
            )
            let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft2")
            store.newTab(document: document)
            let model = WorkspaceModel(tabStore: store)
            let renew = Task { @MainActor in await model.renewRecoveryLifetime(retiredFrom: document) }
            for _ in 0 ..< yields {
                await Task.yield()
            }
            model.tabStore.updateActiveDocument { $0.updatingText("typed \(yields)") }
            await renew.value

            let active = try #require(model.tabStore.activeDocument)
            if active.text != "typed \(yields)" {
                reverted.append(yields)
            }
            if active.recoveryEpoch == document.recoveryEpoch {
                notRenewed.append(yields)
            }
        }
        #expect(reverted.isEmpty, "the edit was reverted at yield offsets \(reverted)")
        #expect(notRenewed.isEmpty, "the window stayed on the retired lifetime at yield offsets \(notRenewed)")
    }

    /// Same shape in the failed-discard path (`preserveOpenDocumentAfterFailedCloseRetirement`): it checked the
    /// document was current before awaiting the persist, then published the older copy.
    @Test func anEditDuringAFailedDiscardPreservationIsKept() async throws {
        var reverted: [Int] = []
        for yields in 0 ..< 60 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let store = TabStore(
                sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("tabs.json")),
                recoveryBuffer: buffer
            )
            let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft2")
            store.newTab(document: document)
            let model = WorkspaceModel(tabStore: store)
            let preserve = Task { @MainActor in await model.preserveOpenDocumentAfterFailedCloseRetirement(document) }
            for _ in 0 ..< yields {
                await Task.yield()
            }
            model.tabStore.updateActiveDocument { $0.updatingText("typed \(yields)") }
            await preserve.value

            if model.tabStore.activeDocument?.text != "typed \(yields)" {
                reverted.append(yields)
            }
        }
        #expect(reverted.isEmpty, "the edit was reverted at yield offsets \(reverted)")
    }

    /// A document that is clean when the lifetime is renewed (a clean close racing an external reload) moves to the new
    /// lifetime but gets no recovery record: nothing would ever remove it and a relaunch after a disk change would
    /// restore it as a false conflict.
    @Test(arguments: [true, false])
    func aCleanDocumentIsRenewedWithoutAStaleRecoveryRecord(viaRenew: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("a.md")
        try "disk text".write(to: file, atomically: true, encoding: .utf8)
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        // Edited then saved: clean, with a non-zero mutation generation (a fresh load's version 0 is never recorded).
        let clean = try FileDocument(fileURL: file, recoveryBuffer: buffer).load().edited(text: "saved text").save()
        #expect(clean.state == .clean)
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("tabs.json")),
            recoveryBuffer: buffer
        )
        store.newTab(document: clean)
        let model = WorkspaceModel(tabStore: store)

        if viaRenew {
            await model.renewRecoveryLifetime(retiredFrom: clean)
        } else {
            await model.preserveOpenDocumentAfterFailedCloseRetirement(clean)
        }

        let renewed = try #require(model.tabStore.activeDocument)
        #expect(renewed.recoveryEpoch != clean.recoveryEpoch, "the document still moves to the new lifetime")
        #expect(renewed.state == .clean)
        let record = try await buffer.load(for: renewed.id, epoch: renewed.recoveryEpoch)
        #expect(record == nil, "but no recovery record is written for clean text")
    }
}

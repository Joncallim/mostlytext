import FileCore
import Foundation
import Testing
@testable import Workspace

/// Review pass 1: a dirty tab restored after a relaunch adopted the file's
/// CURRENT bytes as its baseline, so a change made while the app was quit (a
/// `git pull`, a sync) was silently overwritten by the first Save.
@MainActor
struct RestoredDirtyTabExternalChangeTests {
    @Test func anOlderSessionCannotMistakeANewerABARecoveryEditForCleanText() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("notes.md")
        try "disk v1".write(to: url, atomically: true, encoding: .utf8)
        let loaded = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
        let unavailable = loaded.markingBackingUnavailable(.readFailed("temporary read failure"))
        #expect(await unavailable.persistRecovery())
        let first = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        first.newTab(document: unavailable)
        let oldSession = first.currentSession()
        let editedAway = unavailable.edited(text: "my temporary edit")
        #expect(await editedAway.persistRecovery())
        let editedBack = editedAway.edited(text: "disk v1")
        #expect(await editedBack.persistRecovery())
        try "disk v2".write(to: url, atomically: true, encoding: .utf8)

        let restarted = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let record = try #require(oldSession.tabs.first)
        let restored = try #require(await restarted.restoreTab(from: record))

        #expect(restored.document.text == "disk v1")
        #expect(restored.document.state == .conflict)
        #expect(restored.document.pendingExternalRevision != nil)
        #expect(try await recovery.load(for: loaded.id, epoch: loaded.recoveryEpoch) == "disk v1")
    }

    private func restore(modifyFileAfterQuit modification: ((URL) throws -> Void)?) async throws -> FileDocument {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("notes.md")
        try "disk v1".write(to: url, atomically: true, encoding: .utf8)

        let loaded = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
        let dirty = loaded.updatingText("my unsaved edit")
        #expect(await dirty.persistRecovery())
        let record = TabRecord(
            id: UUID(),
            fileURL: url,
            documentRecoveryEpoch: dirty.recoveryEpoch,
            baseSHA256: dirty.lastKnownRevision?.sha256
        )

        try modification?(url) // while the app is "quit"

        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let tab = try #require(await store.restoreTab(from: record))
        return tab.document
    }

    @Test func aFileChangedWhileTheAppWasQuitComesBackAsAConflictWithTheUnsavedTextIntact() async throws {
        let document = try await restore { try "disk v2 (pulled)".write(to: $0, atomically: true, encoding: .utf8) }

        #expect(document.state == .conflict)
        #expect(document.text == "my unsaved edit")
        #expect(document.pendingExternalRevision != nil)
    }

    /// The monitor binds right after restore and its first probe reads the (changed) disk bytes. That used to
    /// match the document's baseline (the restore had adopted the changed disk as the baseline), so the conflict
    /// was cleared to plain dirty within milliseconds and Save then overwrote the external change.
    @Test func theMonitorsFirstProbeKeepsARestoredConflictAndTheSessionKeepsTheRealBase() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("notes.md")
        try "disk v1".write(to: url, atomically: true, encoding: .utf8)
        let dirty = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
            .updatingText("my unsaved edit")
        #expect(await dirty.persistRecovery())
        let originalBase = try #require(dirty.lastKnownRevision?.sha256)
        let record = TabRecord(
            id: UUID(), fileURL: url, documentRecoveryEpoch: dirty.recoveryEpoch, baseSHA256: originalBase
        )
        try "disk v2 (pulled)".write(to: url, atomically: true, encoding: .utf8)
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let restored = try #require(await store.restoreTab(from: record))
        #expect(restored.document.state == .conflict)

        let probe = try restored.document.reconcilingExternalSnapshot(FileStore().readSnapshot(from: url))

        #expect(probe.document.state == .conflict)
        #expect(probe.disposition == .conflictUpdated)
        #expect(probe.document.text == "my unsaved edit")
        #expect(restored.document.baselineSHA256 == originalBase)
    }

    @Test func anUnchangedFileStillRestoresAsPlainDirty() async throws {
        let document = try await restore(modifyFileAfterQuit: nil)

        #expect(document.state == .dirty)
        #expect(document.text == "my unsaved edit")
    }

    @Test func aSessionWithoutABaselineKeepsTheOldBehaviour() async throws {
        let document = try await {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let url = directory.appendingPathComponent("a.md")
            try "v1".write(to: url, atomically: true, encoding: .utf8)
            let dirty = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
                .updatingText("edit")
            #expect(await dirty.persistRecovery())
            try "v2".write(to: url, atomically: true, encoding: .utf8)
            let record = TabRecord(id: UUID(), fileURL: url, documentRecoveryEpoch: dirty.recoveryEpoch)
            let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
            return try #require(await store.restoreTab(from: record)).document
        }()

        #expect(document.state == .dirty)
    }

    @Test func theBaselineSurvivesARestoreWhileTheFileIsMissingSoALaterReappearanceIsAConflict() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("notes.md")
        try "disk v1".write(to: url, atomically: true, encoding: .utf8)
        let dirty = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
            .updatingText("my unsaved edit")
        #expect(await dirty.persistRecovery())
        let originalBase = try #require(dirty.lastKnownRevision?.sha256)
        let record = TabRecord(
            id: UUID(), fileURL: url, documentRecoveryEpoch: dirty.recoveryEpoch, baseSHA256: originalBase
        )

        // Quit, the file vanishes, relaunch: the tab comes back backing-unavailable.
        try FileManager.default.removeItem(at: url)
        let firstStore = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let unavailable = try #require(await firstStore.restoreTab(from: record))
        firstStore.newTab(id: unavailable.id, document: unavailable.document)
        let rewritten = try #require(firstStore.currentSession().tabs.first)
        #expect(rewritten.baseSHA256 == originalBase)

        // Quit again; the file comes back with different content; relaunch.
        try "disk v2 (restored from backup)".write(to: url, atomically: true, encoding: .utf8)
        let secondStore = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let restored = try #require(await secondStore.restoreTab(from: rewritten))

        #expect(restored.document.state == .conflict)
        #expect(restored.document.text == "my unsaved edit")
    }

    /// A volume that was unmounted at relaunch and comes back with the same bytes is not an external change.
    @Test func aMissingFileReappearingUnchangedIsNotAConflict() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("notes.md")
        try "disk v1".write(to: url, atomically: true, encoding: .utf8)
        let dirty = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
            .updatingText("my unsaved edit")
        #expect(await dirty.persistRecovery())
        let record = TabRecord(
            id: UUID(),
            fileURL: url,
            documentRecoveryEpoch: dirty.recoveryEpoch,
            baseSHA256: dirty.lastKnownRevision?.sha256
        )
        let original = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let unavailable = try #require(await store.restoreTab(from: record))

        try original.write(to: url)
        let probe = try unavailable.document.reconcilingExternalSnapshot(FileStore().readSnapshot(from: url))

        #expect(probe.document.state == .dirty)
        #expect(probe.document.text == "my unsaved edit")
        #expect(probe.document.pendingExternalRevision == nil)
    }
}

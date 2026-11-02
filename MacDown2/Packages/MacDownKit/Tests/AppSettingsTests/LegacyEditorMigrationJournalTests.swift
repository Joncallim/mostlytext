@testable import AppSettings
import Darwin
import Foundation
import Synchronization
import Testing

@Suite("Durable editor journal storage and interruption")
@MainActor
struct LegacyEditorMigrationJournalTests {
    private enum Injected: Error { case interruption }

    @Test func interruptionAtEveryWriteBoundaryLeavesRecoverableEvidence() async throws {
        for operation in 1 ... 3 {
            for boundary in [
                MigrationJournalDirectory.Checkpoint.afterWrite, .afterFileSync, .afterRename, .afterDirectorySync,
            ] {
                let fixture = try EditorMigrationFixture()
                defer { fixture.cleanup() }
                let writes = Mutex(0)
                let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory) { point in
                    let count = writes.withLock { count in
                        if point == .afterWrite {
                            count += 1
                        }
                        return count
                    }
                    if count == operation, point == boundary {
                        throw Injected.interruption
                    }
                }
                let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
                let proposal = try fixture.proposal()
                await #expect(throws: Injected.interruption) {
                    try await boot.start(proposal, currentSource: { try fixture.source() })
                }
                #expect(boot.state == .recoveryRequired)
                if operation == 1 {
                    #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
                } else {
                    #expect(fixture.defaults.data(forKey: "appSettings.editor") == proposal.desiredData)
                }
                await journal.close()
                let reopened = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
                let recovery = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: reopened)
                if try await reopened.inspect() == .empty {
                    #expect(try await recovery.start(proposal, currentSource: { try fixture.source() }) == .applied)
                } else {
                    _ = try await recovery.resume(currentSource: { try fixture.source() })
                }
                #expect(try await reopened.inspect() == .complete)
                #expect(fixture.defaults.data(forKey: "appSettings.editor") == proposal.desiredData)
                await reopened.close()
            }
        }
    }

    @Test func anotherOwnerCannotOpenTheJournalAndCloseReleasesOnlyDescriptors() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let first = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        #expect(throws: LegacyMigrationFailure.busy) {
            try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        }
        let plan = try fixture.plan()
        _ = try await first.prepare(plan)
        await first.close()
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("lock").path))
        let second = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        #expect(try await second.inspect() == .prepared)
        await second.close()
    }

    @Test func invalidFutureDuplicateAndAlteredUnselectedFieldsArePreserved() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let plan = try fixture.plan()
        var object = try #require(JSONSerialization.jsonObject(with: plan.encoded()) as? [String: Any])
        var cases = [Data([255]), Data("{\"version\":1,\"version\":1}".utf8)]
        object["version"] = 2
        try cases.append(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        object["version"] = 1
        object["unknown"] = true
        try cases.append(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        object.removeValue(forKey: "unknown")
        object["selected"] = ["unknown"]
        try cases.append(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        object["selected"] = plan.selected
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        object["desired"] = try encoder.encode(EditorSettings(indentationWidth: 9, smartHome: false))
            .base64EncodedString()
        try cases.append(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        for bytes in cases {
            try fixture.put(bytes, named: "plan.json")
            await #expect(throws: (any Error).self) { try await journal.inspect() }
            #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("plan.json")) == bytes)
            #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
        }
        await journal.close()
    }

    @Test func completionWithoutAcknowledgementAndWrongDigestMarkersAreRefused() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let plan = try fixture.plan()
        _ = try await journal.prepare(plan)
        await #expect(throws: LegacyMigrationFailure.invalidPhase) { try await journal.complete(plan) }
        let marker = Data("{\"phase\":\"complete\",\"planDigest\":\"wrong\",\"version\":1}".utf8)
        try fixture.put(marker, named: "complete.json")
        await #expect(throws: LegacyMigrationFailure.invalidRecord) { try await journal.inspect() }
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("complete.json")) == marker)
        await journal.close()
    }

    @Test func unsafeDirectoryModeSymlinkRecordAndHardLinkedRecordAreNotChanged() async throws {
        for kind in ["mode", "directory-symlink", "record-symlink", "hardlink", "record-mode"] {
            let fixture = try EditorMigrationFixture()
            defer { fixture.cleanup() }
            if kind == "directory-symlink" {
                try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: fixture.root)
                #expect(throws: LegacyMigrationFailure.unsafeStorage) {
                    try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
                }
                continue
            }
            let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
            switch kind {
            case "mode":
                #expect(chmod(fixture.directory.path, 0o755) == 0)
            case "record-symlink":
                try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent("plan.json"),
                                                           withDestinationURL: fixture.directory
                                                               .appendingPathComponent("lock"))
            case "hardlink":
                try fixture.put(Data("preserve".utf8), named: "plan.json")
                try FileManager.default.linkItem(at: fixture.directory.appendingPathComponent("plan.json"),
                                                 to: fixture.directory.appendingPathComponent("other"))
            default:
                try fixture.put(Data("preserve".utf8), named: "plan.json")
                #expect(chmod(fixture.directory.appendingPathComponent("plan.json").path, 0o644) == 0)
            }
            await #expect(throws: LegacyMigrationFailure.unsafeStorage) { try await journal.inspect() }
            #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("lock").path))
            await journal.close()
        }
    }

    @Test func directoryAndLockReplacementAreDetectedWithoutDeletion() async throws {
        for replaceDirectory in [false, true] {
            let fixture = try EditorMigrationFixture()
            defer { fixture.cleanup() }
            let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
            if replaceDirectory {
                try FileManager.default.moveItem(
                    at: fixture.directory,
                    to: fixture.root.appendingPathComponent("saved")
                )
                try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                try fixture.put(Data("replacement".utf8), named: "lock")
            } else {
                try FileManager.default.moveItem(at: fixture.directory.appendingPathComponent("lock"),
                                                 to: fixture.directory.appendingPathComponent("saved-lock"))
                try fixture.put(Data("replacement".utf8), named: "lock")
            }
            await #expect(throws: LegacyMigrationFailure.changedStorage) { try await journal.inspect() }
            await journal.close()
            #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("lock")) == Data("replacement".utf8))
        }
    }
}

@testable import AppSettings
import Darwin
import Foundation
import Testing

@Suite("Journal publication boundary safety")
@MainActor
struct LegacyEditorMigrationSafetyTests {
    @Test func unsafeACLsOnDirectoryLockAndPlanAreRefusedWithoutRepair() async throws {
        for leaf in ["", "lock", "plan.json"] {
            let fixture = try EditorMigrationFixture()
            defer { fixture.cleanup() }
            let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
            _ = try await journal.prepare(fixture.plan())
            let target = leaf.isEmpty ? fixture.directory : fixture.directory.appendingPathComponent(leaf)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+a", "everyone allow read,write", target.path]
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0)
            await #expect(throws: LegacyMigrationFailure.unsafeStorage) { try await journal.inspect() }
            #expect(FileManager.default.fileExists(atPath: target.path))
            await journal.close()
        }
    }

    @Test func aNamedRecordReplacedAfterPublicationIsRetainedAndStopsPreparation() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let path = fixture.directory.appendingPathComponent("plan.json")
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory) { point in
            if point == .afterRename {
                try Data("foreign replacement".utf8).write(to: path, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
        }
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        let proposal = try fixture.proposal()
        await #expect(throws: LegacyMigrationFailure.changedStorage) {
            try await boot.start(proposal, currentSource: { try fixture.source() })
        }
        #expect(try Data(contentsOf: path) == Data("foreign replacement".utf8))
        #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
        await journal.close()
    }

    @Test func failedPreferenceReadbackLeavesOnlyThePreparedPlan() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let defaults = try #require(JournalRefusingDefaults(suiteName: fixture.domain))
        let store = UserDefaultsAppSettingsStore(defaults: defaults, persistenceDomainName: fixture.domain)
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let boot = try LegacyEditorMigrationBootstrap(store: store, journal: journal)
        let proposal = try fixture.proposal()
        await #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.readbackFailed) {
            try await boot.start(proposal, currentSource: { try fixture.source() })
        }
        #expect(try await journal.inspect() == .prepared)
        #expect(!FileManager.default
            .fileExists(atPath: fixture.directory.appendingPathComponent("acknowledged.json").path))
        await journal.close()
    }

    @Test func unknownMarkersAndOversizedRecordsCannotAcknowledgeAnImport() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        try fixture.put(Data("orphan".utf8), named: "acknowledged.json")
        await #expect(throws: LegacyMigrationFailure.invalidRecord) { try await journal.inspect() }
        let raw = Data(repeating: 65, count: MigrationJournalDirectory.maximumBytes + 1)
        try fixture.put(raw, named: "plan.json")
        await #expect(throws: LegacyMigrationFailure.invalidRecord) { try await journal.inspect() }
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("plan.json")) == raw)
        await journal.close()
    }
}

private final class JournalRefusingDefaults: UserDefaults {
    override func set(_: Any?, forKey _: String) {}
}

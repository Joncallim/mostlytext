@testable import AppSettings
import Foundation
import Testing

@Suite("Whole installation conflicts and storage safety")
@MainActor
struct InstallationMigrationSafetyTests {
    @Test func emptyInstallationCompletesWithoutInventingPreferencesAndIgnoresLaterSourceChanges() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        let empty = try InstallationPreferences(application: nil as [String: Any]?, workspace: nil)
        let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(sourcePreferences: empty, currentPreferences: empty)
        let ready = try await fixture.finish(actor, prepared: prepared, source: empty)
        #expect(!ready.hasPreservedDevelopmentState)
        #expect(try fixture.publisher.snapshot().digests == ["absent", "absent"])
        await actor.close()
        try fixture.put("later development data", relative: "session.json")
        let reopened = try fixture.makeActor()
        #expect(try await reopened.resumePublished()?.isComplete == true)
        #expect(!FileManager.default.fileExists(atPath: ready.locations.session.path))
        await reopened.close()
    }

    @Test func scriptOwnerExecutionIntentSurvivesOnlyInWorkingCopyAndNothingExecutes() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        let sentinel = fixture.root.appendingPathComponent("must-not-exist")
        try fixture.put("#!/bin/sh\ntouch '" + sentinel.path + "'", relative: "Commands/owned.sh")
        let original = fixture.development.appendingPathComponent("Commands/owned.sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: original.path)
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        let ready = try await fixture.finish(actor, prepared: prepared, source: source)
        #expect(FileManager.default
            .isExecutableFile(atPath: ready.locations.commands.appendingPathComponent("owned.sh").path))
        #expect(!FileManager.default
            .isExecutableFile(atPath: ready.locations.preservedDirectory.appendingPathComponent("Commands/owned.sh")
                .path))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        await actor.close()
    }

    @Test func aSourceGrantingACLIsRefusedWithoutRepairOrPreferenceWrites() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("source", relative: "session.json")
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/chmod")
        command.arguments = ["+a", "everyone allow read", fixture.development.path]
        try command.run(); command.waitUntilExit()
        #expect(command.terminationStatus == 0)
        let actor = try fixture.makeActor(); let source = try fixture.source()
        await #expect(throws: LegacyMigrationFailure.unsafeStorage) {
            try await actor.prepare(sourcePreferences: source, currentPreferences: fixture.publisher.snapshot())
        }
        #expect(try fixture.publisher.snapshot().digests == ["absent", "absent"])
        #expect(FileManager.default.fileExists(atPath: fixture.development.appendingPathComponent("session.json").path))
        await actor.close()
    }

    @Test func unchangedUnappliedOutputCanBeRetainedAndReplannedAfterSourceDrift() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("before", relative: "session.json")
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        try fixture.put("after", relative: "session.json")
        await #expect(throws: LegacyMigrationFailure.changedStorage) { try await actor.publishFiles(prepared) }
        let retired = try await actor.retireUnapplied(currentPreferences: fixture.publisher.snapshot())
        #expect(retired)
        let second = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        let ready = try await fixture.finish(actor, prepared: second, source: source)
        #expect(try Data(contentsOf: ready.locations.session) == Data("after".utf8))
        let retained = try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path)
        #expect(retained.contains { $0.hasPrefix("retired-plan-") })
        #expect(retained.filter { $0.hasPrefix("installation-stage-") }.count >= 1)
        await actor.close()
    }

    @Test func partialPreferencePublicationKeepsTheSameGenerationAndResumes() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("source", relative: "session.json")
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        let published = try await actor.publishFiles(prepared)
        var interrupted = fixture.publisher
        interrupted.afterDomain = {
            if $0 == 0 {
                throw LegacyMigrationFailure.busy
            }
        }
        #expect(throws: LegacyMigrationFailure.busy) {
            try interrupted.publish(desired: source, before: published.beforePreferenceDigests, revalidateSource: {})
        }
        #expect(try await !actor.retireUnapplied(currentPreferences: fixture.publisher.snapshot()))
        await actor.close()
        let reopened = try fixture.makeActor()
        let existing = try await reopened.resumePublished()
        let resumed = try #require(existing)
        #expect(!resumed.preferencesAcknowledged)
        _ = try await fixture.finish(reopened, prepared: resumed, source: source)
        #expect(try fixture.publisher.snapshot().digests == source.digests)
        await reopened.close()
    }

    @Test func laterWorkingEditsNeverBecomePermissionToRetireAConflict() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("before", relative: "session.json")
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        let published = try await actor.publishFiles(prepared)
        try Data("someone edited this".utf8).write(to: published.locations.session)
        await #expect(throws: LegacyMigrationFailure.changedStorage) {
            try await actor.retireUnapplied(currentPreferences: fixture.publisher.snapshot())
        }
        #expect(try Data(contentsOf: published.locations.session) == Data("someone edited this".utf8))
        await actor.close()
    }

    @Test func completedOriginalImportIsRetainedAsHistoryWithoutRebindingItsOldDomain() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        let snapshot = try LegacyPreferenceSnapshot(domain: ["editorSmartHome": false])
        let raw = try fixture.storeForOriginalProposal()
        let proposal = try LegacyEditorWriteProposal(
            plan: LegacyImportPlan(source: snapshot, destination: .decode(nil)),
            source: snapshot,
            storedDestination: raw,
            selected: [.smartHome]
        )
        let plan = try LegacyEditorJournalPlan(
            proposal: proposal,
            domain: ApplicationStorageLocations.developmentDomain,
            before: nil
        )
        let oldJournal = try LegacyEditorMigrationJournal(directoryURL: fixture.previousJournal)
        _ = try await oldJournal.prepare(plan); try await oldJournal.acknowledge(plan); try await oldJournal
            .complete(plan)
        await oldJournal.close()
        let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: fixture.source(),
            currentPreferences: fixture.publisher.snapshot()
        )
        #expect(prepared.completedOriginalImport)
        #expect(try Data(contentsOf: prepared.locations.preservedDirectory.deletingLastPathComponent()
                .appendingPathComponent("EditorImport/plan.json")) == plan.encoded())
        await actor.close()
    }
}

private extension InstallationFixture {
    func storeForOriginalProposal() throws -> UserDefaultsAppSettingsStore.EditorStoredDomain {
        try UserDefaultsAppSettingsStore(persistentDomainName: appDomain).legacyEditorDestination()
    }
}

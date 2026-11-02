@testable import AppSettings
import Darwin
import Foundation
import Testing

@Suite("Non-destructive whole installation migration")
@MainActor
struct InstallationMigrationTests {
    @Test func independentCopiesPreserveAuthoredBytesAndLaterEditsSurviveRestart() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("# e\u{301}\r\n日本語 👩🏽‍💻", relative: "Recovery/exact.recovery.md")
        try fixture.put("{\"id\":\"stable-theme\"}", relative: "Themes/custom.json")
        try fixture.put("{\"version\":1,\"snippets\":[]}", relative: "snippets.json")
        try fixture.put("#!/bin/sh\nprintf source", relative: "Commands/owned.sh")
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let current = try fixture.publisher.snapshot()
        let prepared = try await actor.prepare(sourcePreferences: source, currentPreferences: current)
        #expect(!prepared.isComplete && prepared.adoptsDevelopment)
        #expect(try fixture.publisher.snapshot().digests == ["absent", "absent"])
        let ready = try await fixture.finish(actor, prepared: prepared, source: source)
        let original = try Data(contentsOf: fixture.development.appendingPathComponent("Recovery/exact.recovery.md"))
        let working = try Data(contentsOf: ready.locations.recovery.appendingPathComponent("exact.recovery.md"))
        let backup = try Data(contentsOf: ready.locations.preservedDirectory
            .appendingPathComponent("Recovery/exact.recovery.md"))
        #expect(original == working && working == backup)
        var workingInfo = stat(); var backupInfo = stat()
        #expect(stat(ready.locations.recovery.appendingPathComponent("exact.recovery.md").path, &workingInfo) == 0)
        #expect(stat(
            ready.locations.preservedDirectory.appendingPathComponent("Recovery/exact.recovery.md").path,
            &backupInfo
        ) ==
            0)
        #expect(workingInfo.st_ino != backupInfo.st_ino)
        #expect(!FileManager.default
            .isExecutableFile(atPath: ready.locations.commands.appendingPathComponent("owned.sh").path))
        try Data("later edit".utf8).write(to: ready.locations.recovery.appendingPathComponent("exact.recovery.md"))
        UserDefaults.standard.setPersistentDomain(["later": true], forName: fixture.appDomain)
        await actor.close()
        let reopened = try fixture.makeActor()
        let historical = try await reopened.resumePublished()
        #expect(historical?.isComplete == true)
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.appDomain)?["later"] as? Bool == true)
        #expect(try Data(contentsOf: ready.locations.preservedDirectory
                .appendingPathComponent("Recovery/exact.recovery.md")) == original)
        await reopened.close()
    }

    @Test func populatedFinalProfileWinsAndDevelopmentBranchIsRecoverable() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("development unsaved", relative: "Recovery/unsaved.recovery.md")
        try FileManager.default.createDirectory(at: fixture.current, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let finalFile = fixture.current.appendingPathComponent("session.json")
        try Data("existing final".utf8).write(to: finalFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: finalFile.path)
        UserDefaults.standard.setPersistentDomain(["deliberate": false], forName: fixture.appDomain)
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        #expect(!prepared.adoptsDevelopment)
        let ready = try await fixture.finish(actor, prepared: prepared, source: source)
        #expect(try String(contentsOf: ready.locations.session, encoding: .utf8) == "existing final")
        #expect(try String(
            contentsOf: ready.locations.preservedDirectory.appendingPathComponent("Recovery/unsaved.recovery.md"),
            encoding: .utf8
        ) == "development unsaved")
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.appDomain)?["deliberate"] as? Bool == false)
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.appDomain)?["appSettings.editor"] == nil)
        await actor.close()
    }

    @Test(arguments: [
        InstallationMigration.Checkpoint.afterPlan, .afterCopy, .afterPublish,
        .afterPreferenceAcknowledgement, .afterComplete,
    ])
    func eachInterruptedBoundaryResumesWithoutDeletingSources(point: InstallationMigration.Checkpoint) async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("\u{feff}untitled\r\n", relative: "Recovery/epoch.recovery.md")
        let source = try fixture.source()
        let actor = try fixture.makeActor {
            if $0 == point {
                throw LegacyMigrationFailure.busy
            }
        }
        do {
            let prepared = try await actor.prepare(
                sourcePreferences: source,
                currentPreferences: fixture.publisher.snapshot()
            )
            _ = try await fixture.finish(actor, prepared: prepared, source: source)
            Issue.record("Expected the injected boundary to interrupt")
        } catch {}
        await actor.close()
        let resumed = try fixture.makeActor()
        let existing = try await resumed.resumePublished()
        let prepared: PreparedInstallationMigration = if let existing {
            existing
        } else {
            try await resumed.prepare(sourcePreferences: source, currentPreferences: fixture.publisher.snapshot())
        }
        if !prepared.isComplete {
            _ = try await fixture.finish(resumed, prepared: prepared, source: source)
        }
        #expect(try Data(contentsOf: fixture.development.appendingPathComponent("Recovery/epoch.recovery.md")) ==
            Data("\u{feff}untitled\r\n".utf8))
        #expect(try fixture.publisher.snapshot().digests == source.digests)
        await resumed.close()
    }

    @Test func sourceDriftAndDestinationDriftNeverOverwriteLaterValues() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        try fixture.put("before", relative: "session.json")
        let source = try fixture.source(); let actor = try fixture.makeActor()
        let prepared = try await actor.prepare(
            sourcePreferences: source,
            currentPreferences: fixture.publisher.snapshot()
        )
        try fixture.put("after", relative: "session.json")
        await #expect(throws: LegacyMigrationFailure.changedStorage) { try await actor.publishFiles(prepared) }
        #expect(try fixture.publisher.snapshot().digests == ["absent", "absent"])
        await actor.close()
        UserDefaults.standard.setPersistentDomain(["later": true], forName: fixture.appDomain)
        #expect(throws: LegacyMigrationFailure.transactionExists) {
            try fixture.publisher.publish(desired: source, before: ["absent", "absent"], revalidateSource: {})
        }
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.appDomain)?["later"] as? Bool == true)
    }

    @Test func partialDefaultsPublicationResumesButNeverRollsBackAThirdValue() throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        let source = try fixture.source()
        var interrupted = fixture.publisher
        interrupted.afterDomain = {
            if $0 == 0 {
                throw LegacyMigrationFailure.busy
            }
        }
        #expect(throws: LegacyMigrationFailure.busy) {
            try interrupted.publish(desired: source, before: ["absent", "absent"], revalidateSource: {})
        }
        try fixture.publisher.publish(desired: source, before: ["absent", "absent"], revalidateSource: {})
        #expect(try fixture.publisher.snapshot().digests == source.digests)
        UserDefaults.standard.setPersistentDomain(["later": "edited"], forName: fixture.workspaceDomain)
        #expect(throws: LegacyMigrationFailure.transactionExists) {
            try fixture.publisher.publish(desired: source, before: ["absent", "absent"], revalidateSource: {})
        }
    }

    @Test func unsafeSourceLinksAndOwnershipModesAreRefused() async throws {
        for symbolic in [true, false] {
            let fixture = try InstallationFixture(); defer { fixture.cleanup() }
            try fixture.put("owned", relative: "real")
            let alias = fixture.development.appendingPathComponent("alias")
            if symbolic {
                try FileManager.default.createSymbolicLink(
                    at: alias,
                    withDestinationURL: fixture.development.appendingPathComponent("real")
                )
            } else {
                try FileManager.default.linkItem(at: fixture.development.appendingPathComponent("real"), to: alias)
            }
            let actor = try fixture.makeActor(); let source = try fixture.source()
            await #expect(throws: LegacyMigrationFailure.unsafeStorage) {
                try await actor.prepare(sourcePreferences: source, currentPreferences: fixture.publisher.snapshot())
            }
            await actor.close()
        }
    }

    @Test func aSecondActorCannotConstructWritersUntilTheFirstOwnerCloses() async throws {
        let fixture = try InstallationFixture(); defer { fixture.cleanup() }
        let actor = try fixture.makeActor()
        #expect(throws: LegacyMigrationFailure.busy) { try fixture.makeActor() }
        await actor.close()
        let second = try fixture.makeActor(); await second.close()
    }
}

@testable import FileCore
import Foundation
import Testing

extension ExternalFileChangesRecoveryTests {
    @Test func cleanTextSurvivesReadFailureThenAdoptsTheNextReadableDiskSnapshot() throws {
        let fixture = try FixtureFile(text: "disk v1")
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let unavailable = loaded.markingBackingUnavailable(.readFailed("temporary read failure"))
        try "disk v2".write(to: fixture.url, atomically: true, encoding: .utf8)

        let outcome = try unavailable.reconcilingExternalSnapshot(FileStore().readSnapshot(from: fixture.url))

        #expect(unavailable.text == "disk v1")
        #expect(unavailable.state == .dirty) // Retain the existing close/recovery protection.
        #expect(outcome.disposition == .reloaded)
        #expect(outcome.document.text == "disk v2")
        #expect(outcome.document.state == .clean)
        #expect(outcome.document.pendingExternalRevision == nil)
    }

    @Test func anEditAfterReadFailureStillConflictsWithTheNextDiskSnapshot() throws {
        let fixture = try FixtureFile(text: "disk v1")
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let edited = loaded.markingBackingUnavailable(.readFailed("temporary read failure"))
            .edited(text: "my edit")
        try "disk v2".write(to: fixture.url, atomically: true, encoding: .utf8)

        let outcome = try edited.reconcilingExternalSnapshot(FileStore().readSnapshot(from: fixture.url))

        #expect(outcome.disposition == .conflicted)
        #expect(outcome.document.text == "my edit")
        #expect(outcome.document.state == .conflict)
    }

    @Test func repeatedReadFailuresKeepTheCleanBaselineButANoopEditRetiresIt() throws {
        let fixture = try FixtureFile(text: "disk v1")
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let first = loaded.markingBackingUnavailable(.readFailed("first"))
        let second = first.markingBackingUnavailable(.readFailed("second"))
        try "disk v2".write(to: fixture.url, atomically: true, encoding: .utf8)
        let snapshot = try FileStore().readSnapshot(from: fixture.url)

        #expect(second.reconcilingExternalSnapshot(snapshot).disposition == .reloaded)
        #expect(second.edited(text: second.text).reconcilingExternalSnapshot(snapshot).disposition == .conflicted)
    }

    @Test func unchangedDiskAfterReadFailureClearsTheProtectiveDirtyState() throws {
        let fixture = try FixtureFile(text: "disk v1")
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let unavailable = loaded.markingBackingUnavailable(.readFailed("temporary read failure"))

        let outcome = try unavailable.reconcilingExternalSnapshot(FileStore().readSnapshot(from: fixture.url))

        #expect(outcome.disposition == .localNowMatchesDisk)
        #expect(outcome.document.state == .clean)
        #expect(outcome.document.unavailableCleanText == nil)
    }

    @Test func migrationRedirectSurvivesRestartUntilPublishedIdentityIsAcknowledged() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recoveryDirectory = fixture.directory.appendingPathComponent("Recovery")
        let sourceEpoch = RecoveryLifetimeEpoch.make()
        let destinationEpoch = RecoveryLifetimeEpoch.make()
        let sourceID = "source"
        let destinationID = "destination"
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        try await recovery.save(content: "draft", for: sourceID, version: 1, epoch: sourceEpoch)

        let outcome = await recovery.migrateWithOutcome(
            from: sourceID,
            to: destinationID,
            content: "draft",
            version: 2,
            sourceEpoch: sourceEpoch,
            destinationEpoch: destinationEpoch
        )
        #expect(outcome.isComplete)

        // Simulate a crash before TabStore publishes its replacement session.
        let beforePublication = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        #expect(try await beforePublication.load(for: sourceID, epoch: sourceEpoch) == "draft")

        let acknowledgement = await recovery.acknowledgeMigration(
            from: sourceID,
            sourceEpoch: sourceEpoch,
            to: destinationID,
            destinationEpoch: destinationEpoch
        )
        #expect(acknowledgement.isAbsent)

        let afterPublication = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        #expect(try await afterPublication.load(for: sourceID, epoch: sourceEpoch) == nil)
        #expect(try await afterPublication.load(for: destinationID, epoch: destinationEpoch) == "draft")
    }

    @Test func reverseMigrationCrashBeforeSessionPublicationFollowsTheFullRedirectChain() async throws {
        let fixture = try FixtureFile(text: "disk")
        let directory = fixture.directory.appendingPathComponent("Recovery")
        let firstEpoch = RecoveryLifetimeEpoch.make()
        let secondEpoch = RecoveryLifetimeEpoch.make()
        let thirdEpoch = RecoveryLifetimeEpoch.make()
        let recovery = RecoveryBuffer(recoveryDirectory: directory)
        try await recovery.save(content: "draft", for: "A", version: 1, epoch: firstEpoch)

        #expect(await recovery.migrateWithOutcome(
            from: "A",
            to: "B",
            content: "draft",
            version: 2,
            sourceEpoch: firstEpoch,
            destinationEpoch: secondEpoch
        ).isComplete)
        #expect(await recovery.migrateWithOutcome(
            from: "B",
            to: "C",
            content: "draft",
            version: 3,
            sourceEpoch: secondEpoch,
            destinationEpoch: thirdEpoch
        ).isComplete)

        // Simulate termination during a rollback/replacement chain, before
        // either caller can publish its replacement session identity.
        let restarted = RecoveryBuffer(recoveryDirectory: directory)
        #expect(try await restarted.load(for: "A", epoch: firstEpoch) == "draft")
        #expect(try await restarted.load(for: "B", epoch: secondEpoch) == "draft")
        #expect(try await restarted.load(for: "C", epoch: thirdEpoch) == "draft")
    }

    @Test func recoveryMigrationRestoresDestinationAfterSourceRemovalBeforeRetirement() async throws {
        let fixture = try FixtureFile(text: "disk")
        let failure = FailOnce()
        let sourceEpoch = RecoveryLifetimeEpoch.make()
        let destinationEpoch = RecoveryLifetimeEpoch.make()
        let recovery = RecoveryBuffer(
            recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(afterSourceRemoval: { _ in try failure.fail() })
        )
        try await recovery.save(content: "source draft", for: "source", version: 1, epoch: sourceEpoch)

        let outcome = await recovery.migrateWithOutcome(
            from: "source",
            to: "destination",
            content: "captured destination draft",
            version: 2,
            sourceEpoch: sourceEpoch,
            destinationEpoch: destinationEpoch
        )
        guard case .failed = outcome else {
            Issue.record("The injected post-removal failure must interrupt retirement")
            return
        }
        let sourceRecovery = await recovery.recoveryLocation(for: "source", epoch: sourceEpoch)
        #expect(!FileManager.default.fileExists(atPath: sourceRecovery.path))

        let restarted = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))
        #expect(try await restarted.load(for: "source", epoch: sourceEpoch) == "captured destination draft")
        #expect(try await restarted.load(for: "destination", epoch: destinationEpoch) == "captured destination draft")
    }

    @Test func unavailableBackingRetainsTextAndMakesItRecoverable() throws {
        let fixture = try FixtureFile(text: "disk")
        let loaded = try FileDocument(fileURL: fixture.url).load()

        let unavailable = loaded.markingBackingUnavailable(.missingOrMoved)

        #expect(unavailable.text == "disk")
        #expect(unavailable.state == .dirty)
        #expect(unavailable.backingState == .unavailable(.missingOrMoved))
    }

    @Test func saveAsUpdatesAllFileIdentityFields() throws {
        let fixture = try FixtureFile()
        let saved = try FileDocument(text: "content").saveAs(fixture.url.appendingPathExtension("txt"))

        #expect(saved.fileURL == fixture.url.appendingPathExtension("txt"))
        #expect(saved.id == fixture.url.appendingPathExtension("txt").absoluteString)
        #expect(saved.format.id == "plaintext")
        #expect(saved.lastKnownRevision?.url == fixture.url.appendingPathExtension("txt").standardizedFileURL)
        #expect(saved.backingState == .available)
        #expect(saved.state == .clean)
    }
}

@testable import AppSettings
import Foundation
import Synchronization
import Testing

@Suite("Journaled editor migration and bootstrap recovery")
@MainActor
struct LegacyEditorMigrationBootstrapTests {
    @Test func startPublishesOnlyAfterTheDurablePlanThenCompletes() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        let proposal = try fixture.proposal()
        boot.afterPreparation = {
            let phase = try await journal.inspect()
            #expect(phase == .prepared)
            #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
        }
        #expect(try await boot.start(proposal, currentSource: { try fixture.source() }) == .applied)
        #expect(boot.state == .ready)
        #expect(try await journal.inspect() == .complete)
        #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] as? Data == proposal
            .desiredData)
        fixture.store.editor = EditorSettings(indentationWidth: 8, smartHome: true)
        #expect(try await boot
            .resume(currentSource: { throw LegacyMigrationFailure.invalidRecord }) == .alreadyCompleted)
        #expect(fixture.store.editor.indentationWidth == 8 && fixture.store.editor.smartHome)
        await journal.close()
    }

    @Test func emptyBootstrapDoesNotCreateAPlanOrReadTheSource() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        #expect(try await boot
            .resume(currentSource: { throw LegacyMigrationFailure.invalidRecord }) == .noPendingTransaction)
        #expect(try await journal.inspect() == .empty)
        #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
        await journal.close()
    }

    @Test func preparedPlanRecoversOnReopenAndRetainsTheSameTransaction() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let plan = try fixture.plan()
        let first = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        _ = try await first.prepare(plan)
        await first.close()
        let reopened = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: reopened)
        #expect(try await boot.resume(currentSource: { try fixture.source() }) == .applied)
        #expect(try await reopened.load().plan?.id == plan.id)
        await reopened.close()
    }

    @Test func desiredBeforeAcknowledgementIsNotRewrittenOrReimported() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let plan = try fixture.plan()
        _ = try await journal.prepare(plan)
        fixture.defaults.set(plan.desired, forKey: "appSettings.editor")
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        #expect(try await boot.resume(currentSource: { throw LegacyMigrationFailure.invalidRecord }) == .alreadyApplied)
        #expect(try await journal.inspect() == .complete)
        await journal.close()
    }

    @Test func acknowledgedPlanPreservesALaterEditIncludingRevertToBefore() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        fixture.store.editor = .default
        let plan = try fixture.plan()
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        _ = try await journal.prepare(plan)
        fixture.defaults.set(plan.desired, forKey: "appSettings.editor")
        try await journal.acknowledge(plan)
        fixture.defaults.set(plan.before, forKey: "appSettings.editor")
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        #expect(try await boot.resume(currentSource: { throw LegacyMigrationFailure.invalidRecord }) == .alreadyApplied)
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == plan.before)
        #expect(fixture.store.editor.smartHome)
        await journal.close()
    }

    @Test func destinationEditDuringPreparationAndSourceDriftCannotPublish() async throws {
        for sourceChanged in [false, true] {
            let fixture = try EditorMigrationFixture()
            defer { fixture.cleanup() }
            let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
            let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
            let proposal = try fixture.proposal()
            boot.afterPreparation = {
                if !sourceChanged {
                    fixture.store.editor = EditorSettings(indentationWidth: 7)
                }
            }
            if sourceChanged {
                await #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.sourceChanged) {
                    try await boot.start(proposal, currentSource: { try fixture.source(true) })
                }
                #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
            } else {
                #expect(try await boot.start(proposal, currentSource: { try fixture.source() }) == .conflict)
                #expect(fixture.store.editor.indentationWidth == 7)
            }
            #expect(try await journal.inspect() == .prepared)
            await journal.close()
        }
    }

    @Test func allPreparedThirdValuesRemainConflicts() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        _ = try await journal.prepare(fixture.plan())
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        for value in [Data([255]), Data("{\"schemaVersion\":2}".utf8), Data("different".utf8)] {
            fixture.defaults.set(value, forKey: "appSettings.editor")
            #expect(try await boot.resume(currentSource: { try fixture.source() }) == .conflict)
            #expect(fixture.defaults.data(forKey: "appSettings.editor") == value)
        }
        fixture.defaults.set("non-data", forKey: "appSettings.editor")
        #expect(try await boot.resume(currentSource: { try fixture.source() }) == .conflict)
        #expect(fixture.defaults.string(forKey: "appSettings.editor") == "non-data")
        await journal.close()
    }

    @Test func aDifferentDomainOrTransactionCannotReuseTheJournal() async throws {
        let fixture = try EditorMigrationFixture()
        let other = try EditorMigrationFixture()
        defer { fixture.cleanup(); other.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        _ = try await journal.prepare(fixture.plan())
        let wrong = try LegacyEditorMigrationBootstrap(store: other.store, journal: journal)
        await #expect(throws: LegacyMigrationFailure.unboundDestination) {
            try await wrong.resume(currentSource: { try other.source() })
        }
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        fixture.store.editor = EditorSettings(indentationWidth: 6)
        let changed = try fixture.proposal()
        await #expect(throws: LegacyMigrationFailure.transactionExists) {
            try await boot.start(changed, currentSource: { try fixture.source() })
        }
        #expect(fixture.store.editor.indentationWidth == 6)
        await journal.close()
    }

    @Test func overlappingBootstrapIsRefusedAndCancellationBeforeWriteIsResumable() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        boot.afterPreparation = {
            await #expect(throws: LegacyMigrationFailure.busy) {
                try await boot.resume(currentSource: { try fixture.source() })
            }
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let proposal = try fixture.proposal()
        let task = Task { try await boot.start(proposal, currentSource: { try fixture.source() }) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await journal.inspect() == .prepared)
        #expect(fixture.defaults.persistentDomain(forName: fixture.domain)?["appSettings.editor"] == nil)
        boot.afterPreparation = nil
        #expect(try await boot.resume(currentSource: { try fixture.source() }) == .applied)
        await journal.close()
    }

    @Test func cancellationAfterReadbackStillRecordsCompletion() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let writes = Mutex(0)
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory) { point in
            if point == .afterWrite {
                let count = writes.withLock { $0 += 1; return $0 }
                if count == 2 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        let proposal = try fixture.proposal()
        let task = Task { try await boot.start(proposal, currentSource: { try fixture.source() }) }
        #expect(try await task.value == .applied)
        #expect(try await journal.inspect() == .complete)
        await journal.close()
    }
}

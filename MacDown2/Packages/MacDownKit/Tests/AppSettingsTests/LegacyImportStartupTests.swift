@testable import AppSettings
import Foundation
import Testing

@Suite("Optional import gates ordinary startup")
@MainActor
struct LegacyImportStartupTests {
    @MainActor private final class SourceBox {
        var value: LegacyPreferenceSnapshot
        init(_ value: LegacyPreferenceSnapshot) {
            self.value = value
        }
    }

    private func startup(_ fixture: EditorMigrationFixture,
                         source: @escaping @MainActor () throws -> LegacyPreferenceSnapshot) -> LegacyImportStartup {
        let directory = fixture.directory
        return LegacyImportStartup(store: fixture.store,
                                   makeJournal: { try LegacyEditorMigrationJournal(directoryURL: directory) },
                                   source: source, resolveFont: { _ in nil })
    }

    @Test func writersWaitForExplicitSelectionAndJournalCompletesBeforeReadiness() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let startup = startup(fixture, source: { try fixture.source() })
        var readyCount = 0
        startup.didBecomeReady = { readyCount += 1 }
        await startup.begin()
        #expect(startup.phase == .review && readyCount == 0)
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == nil)
        await startup.apply(selected: [.smartHome], includeFont: false)
        #expect(startup.phase == .ready && readyCount == 1)
        #expect(!fixture.store.editor.smartHome)
        #expect(fixture.store.editor.convertsTabsToSpaces)
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let phase = try await journal.inspect()
        #expect(phase == .complete)
        await journal.close()
        await startup.begin()
        await startup.continueWithoutImporting()
        #expect(readyCount == 1)
    }

    @Test func skipWritesOnlyDismissalAndSuppressesTheSameSource() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let first = startup(fixture, source: { try fixture.source() })
        await first.begin()
        await first.continueWithoutImporting()
        #expect(first.phase == .ready)
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == nil)
        let same = startup(fixture, source: { try fixture.source() })
        await same.begin()
        #expect(same.phase == .ready)
        let changed = startup(fixture, source: { try fixture.source(true) })
        await changed.begin()
        #expect(changed.phase == .review)
        await changed.continueWithoutImporting()
    }

    @Test func staleConsentNeverPublishesAndBlockedSkipKeepsBytes() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let source = try SourceBox(fixture.source())
        let startup = startup(fixture, source: { source.value })
        await startup.begin()
        source.value = try fixture.source(true)
        await startup.apply(selected: [.smartHome], includeFont: false)
        #expect(startup.phase == .blocked)
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == nil)
        await startup.continueWithoutImporting()
        #expect(startup.phase == .ready)
        #expect(!fixture.store.hasDismissedLegacyImport(source.value.canonicalDigest))
    }

    @Test func concurrentLegacyProcessAndStorageFailuresBlockUntilDeliberateContinue() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let busy = startup(fixture, source: { throw LegacyMigrationFailure.busy })
        await busy.begin()
        #expect(busy.phase == .blocked)
        await busy.continueWithoutImporting()
        #expect(busy.phase == .ready)
        let failed = LegacyImportStartup(
            store: fixture.store,
            makeJournal: { throw LegacyMigrationFailure.unsafeStorage },
            source: { try fixture.source() },
            resolveFont: { _ in nil }
        )
        await failed.begin()
        #expect(failed.phase == .blocked)
        await failed.continueWithoutImporting()
        #expect(failed.phase == .ready)
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == nil)
    }

    @Test func completedJournalDoesNotReadSourceOrOverwriteLaterEdits() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let first = startup(fixture, source: { try fixture.source() })
        await first.begin()
        await first.apply(selected: [.smartHome], includeFont: false)
        fixture.store.editor = EditorSettings(indentationWidth: 8, smartHome: true)
        let later = startup(fixture, source: { throw LegacyMigrationFailure.busy })
        await later.begin()
        #expect(later.phase == .ready)
        #expect(fixture.store.editor.indentationWidth == 8 && fixture.store.editor.smartHome)
    }

    @MainActor private final class InspectionGate {
        var entered = false
        var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            await withCheckedContinuation {
                entered = true
                continuation = $0
            }
        }
    }

    @Test func continuationCannotBypassAnInProgressInspection() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let directory = fixture.directory
        let gate = InspectionGate()
        let startup = LegacyImportStartup(store: fixture.store, makeJournal: {
            await gate.pause()
            return try LegacyEditorMigrationJournal(directoryURL: directory)
        }, source: { try fixture.source() }, resolveFont: { _ in nil })
        let operation = Task { await startup.begin() }
        while !gate.entered {
            await Task.yield()
        }
        await startup.continueWithoutImporting()
        await startup.apply(selected: [.smartHome], includeFont: false)
        #expect(startup.phase == .inspecting)
        gate.continuation?.resume()
        await operation.value
        #expect(startup.phase == .review)
        await startup.continueWithoutImporting()
    }

    @Test func hostBypassNeverTouchesSourceOrJournal() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let startup = LegacyImportStartup(store: fixture.store, disabled: true,
                                          makeJournal: { throw LegacyMigrationFailure.invalidRecord },
                                          source: { throw LegacyMigrationFailure.busy }, resolveFont: { _ in nil })
        await startup.begin()
        #expect(startup.phase == .ready)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test func invalidJournalBlocksWithoutReadingSourceAndSurvivesSkipping() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        await journal.close()
        let future = Data("{\"version\":999}".utf8)
        try fixture.put(future, named: "plan.json")
        var sourceReads = 0
        let startup = startup(fixture, source: { sourceReads += 1; return try fixture.source() })
        await startup.begin()
        #expect(startup.phase == .blocked && sourceReads == 0)
        await startup.continueWithoutImporting()
        #expect(startup.phase == .ready)
        let retained = try Data(contentsOf: fixture.directory.appendingPathComponent("plan.json"))
        #expect(retained == future)
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == nil)
    }
}

@testable import AppSettings
import Foundation
import Testing

@Suite("Exact legacy font conversion and durable replay")
@MainActor
struct LegacyFontImportTests {
    private func source() throws -> LegacyPreferenceSnapshot {
        try LegacyPreferenceSnapshot(domain: ["editorBaseFontInfo": ["name": "Fixture-Regular", "size": 14]])
    }

    private func resolved(_ source: LegacyPreferenceSnapshot, name: String = "Fixture-Regular",
                          size: Double = 14) throws -> LegacyResolvedFont? {
        let entry = try #require(LegacyPreferenceReport(snapshot: source).entries.first)
        guard case let .requiresExactInstalledFont(request) = entry.disposition else { return nil }
        return LegacyResolvedFont(request: request, installedName: "Fixture-Regular", installedFamily: "Fixture",
                                  installedSize: 14, familyResolvedName: name, familyResolvedSize: size)
    }

    @Test func familySubstitutionFaceAndSizeChangesNeverBecomeExact() throws {
        let source = try source()
        #expect(try resolved(source) != nil)
        #expect(try resolved(source, name: "Fixture-Bold") == nil)
        #expect(try resolved(source, name: "Fallback-Regular") == nil)
        #expect(try resolved(source, size: 13) == nil)
    }

    @Test func fontOnlyProposalRequiresReplacementConsentAndPreservesUnselectedSettings() throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        fixture.store.editor = EditorSettings(wrapsLines: false, indentationWidth: 7, smartHome: false)
        let source = try source()
        let observed = try resolved(source)
        let font = try #require(observed)
        let raw = try fixture.store.legacyEditorDestination()
        guard case let .decoded(evidence) = raw else { return }
        let plan = LegacyImportPlan(source: source, destination: evidence)
        #expect(throws: LegacyEditorWriteProposal.Failure.replacementConsentRequired) {
            try LegacyEditorWriteProposal(plan: plan, source: source, storedDestination: raw, selected: [], font: font)
        }
        let proposal = try LegacyEditorWriteProposal(plan: plan, source: source, storedDestination: raw,
                                                     selected: [], font: font, replacingFont: true)
        let changed = try #require(LegacyEditorDestinationEvidence.decode(proposal.desiredData).settings)
        var expected = fixture.store.editor
        expected.font = font.descriptor
        #expect(changed == expected)
        #expect(proposal.mappingVersion == 2)
    }

    @Test func changedInstalledFaceBlocksPreparedFontButRecoveryCanFinishLater() async throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        let source = try source()
        let observed = try resolved(source)
        let font = try #require(observed)
        let raw = try fixture.store.legacyEditorDestination()
        guard case let .decoded(evidence) = raw else { return }
        let proposal = try LegacyEditorWriteProposal(plan: LegacyImportPlan(source: source, destination: evidence),
                                                     source: source, storedDestination: raw, selected: [], font: font)
        let journal = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let boot = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: journal)
        boot.resolveFont = { _ in nil }
        await #expect(throws: UserDefaultsAppSettingsStore.LegacyPublicationFailure.sourceChanged) {
            try await boot.start(proposal, currentSource: { source })
        }
        #expect(fixture.defaults.data(forKey: "appSettings.editor") == nil)
        let phase = try await journal.inspect()
        #expect(phase == .prepared)
        await journal.close()
        let reopened = try LegacyEditorMigrationJournal(directoryURL: fixture.directory)
        let resumed = try LegacyEditorMigrationBootstrap(store: fixture.store, journal: reopened)
        resumed.resolveFont = { _ in font }
        let result = try await resumed.resume(currentSource: { source })
        #expect(result == .applied)
        #expect(fixture.store.editor.font == font.descriptor)
        fixture.store.editor = .default
        resumed.resolveFont = { _ in nil }
        let completed = try await resumed.resume(currentSource: { throw LegacyMigrationFailure.busy })
        #expect(completed == .alreadyCompleted)
        #expect(fixture.store.editor.font == .systemMonospacedDefault)
        await reopened.close()
    }

    @Test func aJournalCannotAlterUnselectedScalarDistinctFontNames() throws {
        let fixture = try EditorMigrationFixture()
        defer { fixture.cleanup() }
        fixture.store.editor = EditorSettings(font: FontDescriptor(familyName: "\u{e9}", size: 14))
        let original = try fixture.plan().encoded()
        let recordObject = try JSONSerialization.jsonObject(with: original)
        var record = try #require(recordObject as? [String: Any])
        let desired = try #require(record["desired"] as? String)
        let bytes = try #require(Data(base64Encoded: desired))
        let settingsObject = try JSONSerialization.jsonObject(with: bytes)
        var settings = try #require(settingsObject as? [String: Any])
        settings["font"] = ["familyName": "e\u{301}", "size": 14]
        record["desired"] = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
            .base64EncodedString()
        let altered = try JSONSerialization.data(
            withJSONObject: record,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        #expect(throws: LegacyMigrationFailure.invalidRecord) { try LegacyEditorJournalPlan.decode(altered) }
    }

    @Test func legacyThemeNamesNeverAliasCurrentThemes() throws {
        for name in ["Tomorrow", "Tomorrow+", "Tomorrow Blue", "Daybreak", "tomorrow-dark", "Custom"] {
            let snapshot = try LegacyPreferenceSnapshot(domain: ["editorStyleName": name])
            #expect(LegacyPreferenceReport(snapshot: snapshot).entries.first?.disposition == .unsupportedLegacyTheme)
            #expect(LegacyImportPlan(source: snapshot, destination: .decode(nil)).entries.isEmpty)
        }
    }
}

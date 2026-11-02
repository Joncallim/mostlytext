import AppSettings
import Foundation
import Testing

@Suite("Legacy editor write preparation and replay")
struct LegacyEditorWriteProposalTests {
    private func source(_ value: Bool = false) throws -> LegacyPreferenceSnapshot {
        try LegacyPreferenceSnapshot(domain: ["editorSmartHome": value, "editorConvertTabs": false])
    }

    private func proposal(
        source: LegacyPreferenceSnapshot,
        raw: Data? = nil,
        selected: Set<LegacyImportPlan.Destination> = [.smartHome],
        replacing: Set<LegacyImportPlan.Destination> = []
    ) throws -> LegacyEditorWriteProposal {
        let destination = LegacyEditorDestinationEvidence.decode(raw)
        return try LegacyEditorWriteProposal(
            plan: LegacyImportPlan(source: source, destination: destination),
            source: source, storedDestination: .decoded(destination), selected: selected, replacing: replacing
        )
    }

    @Test func absentDomainUsesOnlySelectedExplicitValues() throws {
        let source = try source()
        let proposed = try proposal(source: source)
        let decoded = try JSONDecoder().decode(EditorSettings.self, from: proposed.desiredData)
        #expect(!decoded.smartHome)
        #expect(decoded.convertsTabsToSpaces)
        #expect(decoded.font == EditorSettings.default.font)
        #expect(proposed.beforeRevision == "absent")
        #expect(proposed.selected == [.smartHome])
        #expect(proposed.sourceDigest == source.canonicalDigest)
    }

    @Test func existingValuesRequirePerFieldConsentEvenAtDefaults() throws {
        let raw = try JSONEncoder().encode(EditorSettings.default)
        #expect(throws: LegacyEditorWriteProposal.Failure.replacementConsentRequired) {
            try proposal(source: source(), raw: raw)
        }
        #expect(throws: LegacyEditorWriteProposal.Failure.replacementConsentRequired) {
            try proposal(source: source(), raw: raw, selected: [.smartHome, .convertsTabsToSpaces],
                         replacing: [.smartHome])
        }
    }

    @Test func selectedReplacementKeepsEveryUnselectedSetting() throws {
        var expected = EditorSettings(font: FontDescriptor(familyName: "Custom Family", size: 19),
                                      wrapsLines: false, showsInvisibles: true, showsStatusBar: false,
                                      indentationWidth: 7, assistsEnabled: false,
                                      continuesMarkdownPrefixes: false, completesMatchingCharacters: false,
                                      autoIncrementOrderedLists: false)
        let raw = try JSONEncoder().encode(expected)
        let proposed = try proposal(source: source(), raw: raw, replacing: [.smartHome])
        expected.smartHome = false
        #expect(try JSONDecoder().decode(EditorSettings.self, from: proposed.desiredData) == expected)
    }

    @Test func changedSourceOrRawDestinationInvalidatesConsent() throws {
        let captured = try source()
        let destination = LegacyEditorDestinationEvidence.decode(nil)
        let plan = LegacyImportPlan(source: captured, destination: destination)
        #expect(throws: LegacyEditorWriteProposal.Failure.stalePlan) {
            try LegacyEditorWriteProposal(plan: plan, source: source(true), storedDestination: .decoded(destination),
                                          selected: [.smartHome])
        }
        let raw = try JSONEncoder().encode(EditorSettings.default)
        let stored = LegacyEditorDestinationEvidence.decode(raw)
        let storedPlan = LegacyImportPlan(source: captured, destination: stored)
        #expect(throws: LegacyEditorWriteProposal.Failure.stalePlan) {
            try LegacyEditorWriteProposal(plan: storedPlan, source: captured,
                                          storedDestination: .decoded(.decode(Data(" ".utf8) + raw)),
                                          selected: [.smartHome], replacing: [.smartHome])
        }
    }

    @Test func unreadableAndFutureDomainsNeverProduceReplacementBytes() throws {
        for raw in [
            Data([255]), Data("{\"schemaVersion\":2}".utf8),
            Data("{\"schemaVersion\":1,\"schemaVersion\":1}".utf8),
        ] {
            #expect(throws: LegacyEditorWriteProposal.Failure.unavailableDestination) {
                try proposal(source: source(), raw: raw, replacing: [.smartHome])
            }
        }
    }

    @Test func unproposedOrEmptySelectionsCannotAuthorizeChanges() throws {
        #expect(throws: LegacyEditorWriteProposal.Failure.unproposedSelection) {
            try proposal(source: source(), selected: [.autoIncrementOrderedLists])
        }
        #expect(throws: LegacyEditorWriteProposal.Failure.noSelectedChanges) {
            try proposal(source: source(), selected: [])
        }
        #expect(throws: LegacyEditorWriteProposal.Failure.unproposedSelection) {
            try proposal(source: source(), replacing: [.convertsTabsToSpaces])
        }
    }

    @Test func replayRecognizesItsOwnWriteAndPreservesThirdValues() throws {
        let proposed = try proposal(source: source())
        #expect(proposed.replayDisposition(current: .decoded(.decode(nil))) == .readyToWrite)
        #expect(proposed.replayDisposition(current: .decoded(.decode(proposed.desiredData))) == .alreadyApplied)
        let changed = try JSONEncoder().encode(EditorSettings(font: .init(familyName: "Later Edit", size: 18)))
        #expect(proposed.replayDisposition(current: .decoded(.decode(changed))) == .conflict)
        #expect(proposed.replayDisposition(current: .decoded(.decode(Data([255])))) == .conflict)
    }

    @Test func identicalInputAndSelectionProduceIdenticalBytes() throws {
        let source = try source()
        let first = try proposal(source: source, selected: [.smartHome, .convertsTabsToSpaces])
        let second = try proposal(source: source, selected: [.convertsTabsToSpaces, .smartHome])
        #expect(first == second)
        #expect(first.desiredRevision == LegacyEditorDestinationEvidence.decode(first.desiredData).rawRevision)
    }

    @Test func nonDataStoredValueBlocksPreparationAndReplay() throws {
        let source = try source()
        let destination = LegacyEditorDestinationEvidence.decode(nil)
        let plan = LegacyImportPlan(source: source, destination: destination)
        #expect(throws: LegacyEditorWriteProposal.Failure.unavailableDestination) {
            try LegacyEditorWriteProposal(plan: plan, source: source, storedDestination: .unreadableNonData,
                                          selected: [.smartHome], replacing: [.smartHome])
        }
        let proposed = try proposal(source: source)
        #expect(proposed.replayDisposition(current: .unreadableNonData) == .conflict)
    }
}

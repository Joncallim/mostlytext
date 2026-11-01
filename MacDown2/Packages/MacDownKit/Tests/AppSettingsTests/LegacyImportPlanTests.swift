@testable import AppSettings
import Foundation
import Testing

@Suite("Read-only legacy import plan")
struct LegacyImportPlanTests {
    private func source(_ values: [String: Any] = [
        "editorAutoIncrementNumberedLists": false,
        "editorConvertTabs": true,
        "editorSmartHome": false,
    ]) throws -> LegacyPreferenceSnapshot {
        try LegacyPreferenceSnapshot(domain: values)
    }

    private func editorData(smartHome: Bool = false) throws -> Data {
        try JSONEncoder().encode(EditorSettings(
            convertsTabsToSpaces: false, smartHome: smartHome,
            autoIncrementOrderedLists: true
        ))
    }

    @Test func missingDomainCanProposeOnlyExplicitSourceValues() throws {
        let evidence = LegacyEditorDestinationEvidence.decode(nil)
        let plan = try LegacyImportPlan(source: source(), destination: evidence)
        #expect(plan.defaultFills == [
            .autoIncrementOrderedLists: false,
            .convertsTabsToSpaces: true,
            .smartHome: false,
        ])
        #expect(plan.destinationRevision == "absent")
    }

    @Test func validPersistedValuesWinEvenWhenEqualToDefaults() throws {
        let evidence = try LegacyEditorDestinationEvidence.decode(editorData())
        let plan = try LegacyImportPlan(source: source(), destination: evidence)
        #expect(evidence.status == .valid)
        #expect(plan.defaultFills.isEmpty)
        #expect(plan.entries.first { $0.destination == .smartHome }?.disposition ==
            .retainPersisted(false, suggested: false))
        #expect(plan.entries.first { $0.destination == .autoIncrementOrderedLists }?.disposition ==
            .retainPersisted(true, suggested: false))
        #expect(plan.entries.first { $0.destination == .convertsTabsToSpaces }?.disposition ==
            .retainPersisted(false, suggested: true))
    }

    @Test func unreadableOrFuturePrimaryBlocksAutomaticFills() throws {
        let malformed = LegacyEditorDestinationEvidence.decode(Data("not json".utf8))
        let future = LegacyEditorDestinationEvidence.decode(Data("{\"schemaVersion\":2}".utf8))
        for evidence in [malformed, future] {
            let plan = try LegacyImportPlan(source: source(), destination: evidence)
            #expect(plan.defaultFills.isEmpty)
            #expect(plan.entries.count == 3)
            #expect(plan.entries.allSatisfy { entry in
                entry.disposition == .blockedUnreadable || entry.disposition == .blockedFutureVersion
            })
        }
    }

    @Test func sourceAndExactRawDestinationRevisionsBindThePlan() throws {
        let captured = try source()
        let raw = try editorData()
        let evidence = LegacyEditorDestinationEvidence.decode(raw)
        let plan = LegacyImportPlan(source: captured, destination: evidence)
        #expect(plan.matches(source: captured, destination: evidence))
        #expect(try !plan.matches(source: source(["editorSmartHome": true]), destination: evidence))
        let equivalentButDifferentBytes = Data(" \n".utf8) + raw
        let recaptured = LegacyEditorDestinationEvidence.decode(equivalentButDifferentBytes)
        #expect(recaptured.status == evidence.status)
        #expect(!plan.matches(source: captured, destination: recaptured))
        #expect(try !plan.matches(source: captured,
                                  destination: .decode(editorData(smartHome: true))))
    }

    @Test func invalidSourceValuesAreReportedButNotProposed() throws {
        let plan = try LegacyImportPlan(
            source: source(["editorSmartHome": "false", "editorConvertTabs": true]),
            destination: .decode(nil)
        )
        #expect(plan.defaultFills == [.convertsTabsToSpaces: true])
        #expect(plan.invalidSourceKeys == ["editorSmartHome"])
    }
}

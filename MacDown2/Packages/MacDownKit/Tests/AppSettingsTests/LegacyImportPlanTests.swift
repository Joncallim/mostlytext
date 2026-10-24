@testable import AppSettings
import Foundation
import Testing

@Suite("Read-only legacy import plan")
struct LegacyImportPlanTests {
    typealias Destination = LegacyEditorBooleanConversion.Destination

    private func source(_ values: [String: Any] = [
        "editorAutoIncrementNumberedLists": false,
        "editorConvertTabs": true,
        "editorSmartHome": false,
    ]) throws -> LegacyPreferenceSnapshot {
        try LegacyPreferenceSnapshot(domain: values)
    }

    @Test func missingDomainCanProposeOnlyExplicitSourceValues() throws {
        let plan = try LegacyImportPlan(source: source(), destination: .absent, destinationRevision: "absent-1")
        #expect(plan.defaultFills == [
            .autoIncrementOrderedLists: false,
            .convertsTabsToSpaces: true,
            .smartHome: false,
        ])
        #expect(plan.entries.count == 3)
    }

    @Test func validPersistedValueWinsEvenIfItEqualsTheDefault() throws {
        let plan = try LegacyImportPlan(
            source: source(),
            destination: .valid(
                persisted: [.autoIncrementOrderedLists: true, .smartHome: false],
                provenAbsent: [.convertsTabsToSpaces]
            ),
            destinationRevision: "valid-2"
        )
        #expect(plan.defaultFills == [.convertsTabsToSpaces: true])
        #expect(plan.entries.first { $0.destination == .autoIncrementOrderedLists }?.disposition ==
            .retainPersisted(true, suggested: false))
        #expect(plan.entries.first { $0.destination == .smartHome }?.disposition ==
            .retainPersisted(false, suggested: false))
    }

    @Test func unprovenAbsenceCannotBecomeAPersistedChange() throws {
        let plan = try LegacyImportPlan(
            source: source(), destination: .valid(persisted: [:], provenAbsent: []),
            destinationRevision: "unknown-3"
        )
        #expect(plan.defaultFills.isEmpty)
        #expect(plan.entries.allSatisfy { $0.disposition == .blockedUnknownPresence })
    }

    @Test(arguments: [LegacyEditorDestinationDomain.unreadable, .futureVersion])
    func unsupportedPrimaryBlocksAllAutomaticFills(_ destination: LegacyEditorDestinationDomain) throws {
        let plan = try LegacyImportPlan(source: source(), destination: destination, destinationRevision: "raw-4")
        #expect(plan.defaultFills.isEmpty)
        #expect(plan.entries.count == 3)
        #expect(plan.entries.allSatisfy { entry in
            entry.disposition == .blockedUnreadable || entry.disposition == .blockedFutureVersion
        })
    }

    @Test func sourceAndDestinationRevisionsAreBothBoundToThePlan() throws {
        let captured = try source()
        let plan = LegacyImportPlan(source: captured, destination: .absent, destinationRevision: "revision-A")
        #expect(plan.matches(source: captured, destinationRevision: "revision-A"))
        #expect(!plan.matches(source: captured, destinationRevision: "revision-B"))
        #expect(try !plan.matches(source: source(["editorSmartHome": true]), destinationRevision: "revision-A"))
    }

    @Test func invalidSourceValuesAreReportedButNotProposed() throws {
        let plan = try LegacyImportPlan(
            source: source(["editorSmartHome": "false", "editorConvertTabs": true]),
            destination: .absent,
            destinationRevision: "absent-5"
        )
        #expect(plan.defaultFills == [.convertsTabsToSpaces: true])
        #expect(plan.invalidSourceKeys == ["editorSmartHome"])
    }
}

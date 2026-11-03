import ExportService
import Foundation
@testable import MacDown2
import Testing

@MainActor
struct ExportOriginLeasePolicyTests {
    @Test func ordinaryUnfrozenInputsStillRejectIdentityAndScopeChanges() {
        let identity = ExportLifetimeLease()
        let scope = ExportLifetimeLease()
        WeakValidatedExportLease(identity, ordinary: true).sourceIdentityWillChange(from: UUID(), to: UUID())
        WeakValidatedExportLease(scope, ordinary: true).sourceScopeWillChange()
        #expect(throws: CancellationError.self) { try identity.checkActive() }
        #expect(throws: CancellationError.self) { try scope.checkActive() }
    }

    @Test func frozenOrdinaryInputsSurviveSaveAsAndScopeChangesWithinTheirTab() throws {
        let lease = ExportLifetimeLease()
        let entry = WeakValidatedExportLease(lease, ordinary: true)
        let tab = UUID()
        entry.didFreezeOrdinaryInputs(tabID: tab)
        entry.sourceIdentityWillChange(from: tab, to: tab)
        entry.sourceScopeWillChange()
        try lease.withPublicationCutoff {}
    }

    @Test(arguments: [true, false]) func frozenOrdinaryInputsRejectTabSwitchOrRemoval(removal: Bool) {
        let lease = ExportLifetimeLease()
        let entry = WeakValidatedExportLease(lease, ordinary: true)
        let tab = UUID()
        entry.didFreezeOrdinaryInputs(tabID: tab)
        entry.sourceIdentityWillChange(from: tab, to: removal ? nil : UUID())
        #expect(throws: CancellationError.self) { try lease.withPublicationCutoff {} }
    }

    @Test func disabledValidatedInputsAlwaysRetainStrictIdentityPolicy() {
        let lease = ExportLifetimeLease()
        let entry = WeakValidatedExportLease(lease, ordinary: false)
        let tab = UUID()
        entry.didFreezeOrdinaryInputs(tabID: tab)
        entry.sourceIdentityWillChange(from: tab, to: tab)
        #expect(throws: CancellationError.self) { try lease.checkActive() }
    }
}

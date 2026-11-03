import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportPublicationRecoveryTests {
    private typealias Fixture = ExportPrimaryRecoveryTestSupport.Fixture

    @Test func ordinaryExportReconcilesADurableReceiptBeforeCheckingUnknownResidue() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let result = try ExportFileWriter.writeHTML(
            ExportPublicationTestSupport.prepared(),
            to: .html(url: fixture.primary, mode: .standalone(style: .embedded)), recovery: fixture.location
        )
        #expect(result.primaryFile == fixture.primary)
        #expect(try Data(contentsOf: fixture.primary) != fixture.old)
        #expect(try ExportPublicationFilesystem.primaryBaseline(name, in: fixture.descriptor) == nil)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func successfulPromotionReturnsAWarningWhenFinalizationFails() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let prepared = try ExportPublicationTestSupport.prepared()
        let hooks = ExportPublicationHooks(beforeJournalFinalization: { throw ExportError.unsafePublication })
        let target = ExportTarget.html(url: fixture.primary, mode: .selfContained)
        let result = try ExportFileWriter.writeHTML(prepared, to: target, hooks: hooks, recovery: fixture.location)
        #expect(result.diagnostics.contains { $0.severity == .warning && $0.message.contains("export was saved") })
        let original = try Data(contentsOf: fixture.primary)
        #expect(!original.isEmpty)
        #expect(try fixture.store().record.pending != nil)
        let next = try ExportFileWriter.writeHTML(prepared, to: target, recovery: fixture.location)
        #expect(!next.diagnostics.contains { $0.message.contains("recovery record") })
        #expect(try Data(contentsOf: fixture.primary) == original)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func cancellationBeforePromotionKeepsThePriorPrimaryAndReconcilesLater() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.old.write(to: fixture.primary)
        let prepared = try ExportPublicationTestSupport.prepared()
        let lease = ExportLifetimeLease()
        let target = ExportTarget.html(url: fixture.primary, mode: .selfContained)
        let hooks = ExportPublicationHooks(beforePromotion: { lease.revoke() })
        #expect(throws: CancellationError.self) {
            _ = try ExportFileWriter.writeHTML(
                prepared,
                to: target,
                lease: lease,
                hooks: hooks,
                recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        #expect(try fixture.store().record.pending == nil)
        _ = try ExportFileWriter.writeHTML(prepared, to: target, recovery: fixture.location)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func taskCancellationCompletesDurableCleanupWithoutManualRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.old.write(to: fixture.primary)
        let prepared = try ExportPublicationTestSupport.prepared()
        let target = ExportTarget.html(url: fixture.primary, mode: .selfContained)
        let recovery = fixture.location
        let task = Task {
            let hooks = ExportPublicationHooks(beforePromotion: { withUnsafeCurrentTask { $0?.cancel() } })
            #expect(throws: CancellationError.self) {
                _ = try ExportFileWriter.writeHTML(prepared, to: target, hooks: hooks, recovery: recovery)
            }
        }
        await task.value
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        #expect(try fixture.store().record.pending == nil)
        _ = try ExportFileWriter.writeHTML(prepared, to: target, recovery: fixture.location)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func taskCancellationBeforeReceiptCheckpointRequiresNoManualRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.old.write(to: fixture.primary)
        let prepared = try ExportPublicationTestSupport.prepared()
        let target = ExportTarget.html(url: fixture.primary, mode: .selfContained)
        let recovery = fixture.location
        let task = Task {
            let hooks = ExportPublicationHooks(afterPrimaryStaged: { withUnsafeCurrentTask { $0?.cancel() } })
            #expect(throws: CancellationError.self) {
                _ = try ExportFileWriter.writeHTML(prepared, to: target, hooks: hooks, recovery: recovery)
            }
        }
        await task.value
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        #expect(try fixture.store().record.pending == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.output.path)
        #expect(!names.contains { $0.hasPrefix(".mt-") })
        _ = try ExportFileWriter.writeHTML(prepared, to: target, recovery: recovery)
    }

    @Test func unknownScratchStillBlocksGrowthEvenWhenPrivateStorageIsAvailable() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.old.write(to: fixture.primary)
        let name = ExportPublicationRetention.scratchPrefix(for: fixture.leaf) + UUID().uuidString + ".html.tmp"
        let unknown = Data("unowned staging".utf8)
        try unknown.write(to: fixture.output.appendingPathComponent(name))
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
                recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == unknown)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func oneHundredAlternatingExportsLeaveNoPendingPrimaryOrPublicScratch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for index in 0 ..< 100 {
            let mode: HTMLExportMode = index.isMultiple(of: 2) ? .selfContained : .standalone(style: .embedded)
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(text: "revision \(index)"),
                to: .html(url: fixture.primary, mode: mode), recovery: fixture.location
            )
        }
        #expect(try fixture.store().record.pending == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.output.path)
        #expect(!names.contains { $0.hasPrefix(".mt-") })
        #expect(try String(contentsOf: fixture.primary, encoding: .utf8).contains("revision 99"))
    }
}

@testable import ExportService
import Foundation
import Testing

struct ExportPublicationRetentionTests {
    @Test func scalarDistinctUnknownNamesAreChargedSeparately() throws {
        var retained = ExportPublicationRetention.Retained()
        let limits = ExportRetentionLimit(files: 2, bytes: 10)
        try retained.reserve(name: "Café", bytes: 5, limits: limits)
        try retained.reserve(name: "Cafe\u{0301}", bytes: 5, limits: limits)
        #expect(retained.names.count == 2)
        #expect(retained.bytes == 10)
    }

    @Test func oneHundredModeSwitchesRetainOnlyABoundedFlatNamespace() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let hooks = ExportPublicationHooks(retentionLimit: ExportRetentionLimit(files: 6, bytes: 8192))
        var acceptedCompanion = 0
        var rejectedCompanion = 0
        for index in 0 ..< 100 {
            let prepared = try ExportPublicationTestSupport.prepared(bytes: Data([UInt8(index)]))
            let mode: HTMLExportMode = index.isMultiple(of: 2) ? .standalone(style: .embedded) : .selfContained
            let previous = try? Data(contentsOf: item.primary)
            do {
                _ = try ExportFileWriter.writeHTML(prepared, to: .html(url: item.primary, mode: mode), hooks: hooks)
                if index.isMultiple(of: 2) {
                    acceptedCompanion += 1
                }
            } catch ExportError.budgetExceeded {
                #expect(index.isMultiple(of: 2))
                rejectedCompanion += 1
                #expect(try Data(contentsOf: item.primary) == previous)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: item.assets.path).count <= 6)
        }
        #expect(acceptedCompanion == 5)
        #expect(rejectedCompanion == 45)
    }

    @Test func aggregateRetentionBudgetStopsBeforeAddingANewPayload() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let owner = try ExportAssetOwnerMarker.bytes(primary: "report.html", assets: "report.assets")
        let hooks = ExportPublicationHooks(retentionLimit: ExportRetentionLimit(files: 20, bytes: owner.count + 4))
        _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: item.target, hooks: hooks)
        let before = try Data(contentsOf: item.primary)
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(bytes: Data(repeating: 1, count: 8)),
                to: item.target,
                hooks: hooks
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.assets.path).count == 2)
        #expect(try Data(contentsOf: item.primary) == before)
    }

    @Test func interruptedPrimaryScratchBlocksFurtherGrowthWithoutDeletingIt() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let scratch = item.directory.appendingPathComponent(
            ExportPublicationRetention.scratchPrefix(for: "report.html") + "interrupted.html.tmp"
        )
        try Data("ambiguous retained bytes".utf8).write(to: scratch)
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: item.target)
        }
        #expect(try Data(contentsOf: scratch) == Data("ambiguous retained bytes".utf8))
        #expect(!FileManager.default.fileExists(atPath: item.assets.path))
    }

    @Test func interruptedAssetScratchAndUserFilesRemainUntouched() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let prepared = try ExportPublicationTestSupport.prepared()
        _ = try ExportFileWriter.writeHTML(prepared, to: item.target)
        let scratch = item.assets.appendingPathComponent(".mt-interrupted.stage")
        let user = item.assets.appendingPathComponent("user.txt")
        try Data("retained".utf8).write(to: scratch)
        try Data("user".utf8).write(to: user)
        let before = try Data(contentsOf: item.primary)
        #expect(throws: ExportError.self) { _ = try ExportFileWriter.writeHTML(prepared, to: item.target) }
        #expect(try Data(contentsOf: scratch) == Data("retained".utf8))
        #expect(try Data(contentsOf: user) == Data("user".utf8))
        #expect(try Data(contentsOf: item.primary) == before)
    }
}

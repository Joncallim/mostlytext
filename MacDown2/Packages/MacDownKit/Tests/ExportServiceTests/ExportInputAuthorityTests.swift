@testable import ExportService
import Foundation
import LocalResourceAccess
import Testing

struct ExportInputAuthorityTests {
    @Test func noCapabilityCannotReadLocalImages() throws {
        let subject = ExportResourceResolver(resourceAccess: nil, unresolvedIsFatal: true)
        #expect(try subject.disposition(for: "image.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.count == 1)
        #expect(subject.diagnostics.first?.severity == .error)
    }

    @Test func replacingTheGrantedRootDoesNotAdmitItsReplacement() throws {
        let base = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let access = try ExportResourceAccess(openingDirectory: root)
        try FileManager.default.moveItem(at: root, to: base.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: root.appendingPathComponent("image.png"))
        let subject = ExportResourceResolver(resourceAccess: access, unresolvedIsFatal: false)
        #expect(try subject.disposition(for: "image.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.first?.severity == .warning)
    }

    @Test func anImageLookingAliasCannotPackageANonImageTarget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("private fixture".utf8).write(to: directory.appendingPathComponent("private.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: directory.appendingPathComponent("image.png").path, withDestinationPath: "private.txt"
        )
        let access = try ExportResourceAccess(openingDirectory: directory)
        let subject = ExportResourceResolver(resourceAccess: access, unresolvedIsFatal: true)
        #expect(try subject.disposition(for: "image.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
        #expect(subject.diagnostics.first?.message.contains("not an image file") == true)
    }

    @Test func aSafeAliasUsesTheResolvedImageType() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([0xFF, 0xD8, 0xFF])
        try bytes.write(to: directory.appendingPathComponent("actual.jpg"))
        try FileManager.default.createSymbolicLink(
            atPath: directory.appendingPathComponent("alias.png").path, withDestinationPath: "actual.jpg"
        )
        let subject = try ExportResourceResolver(
            resourceAccess: ExportResourceAccess(openingDirectory: directory), unresolvedIsFatal: true
        )
        #expect(try subject.disposition(for: "alias.png", isImage: true) != .keep)
        let resource = try #require(subject.frozenManifest().resources.first)
        #expect(resource.bytes == bytes)
        #expect(resource.identity.mimeType == "image/jpeg")
    }

    @Test func aClosedCapabilityCannotBeReopenedByPath() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: directory.appendingPathComponent("image.png"))
        let access = try ExportResourceAccess(openingDirectory: directory)
        access.directory.close()
        let subject = ExportResourceResolver(resourceAccess: access, unresolvedIsFatal: true)
        #expect(try subject.disposition(for: "image.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.isEmpty)
    }

    @Test func cancellationIsNotAnUnresolvedImageWarning() throws {
        let cancellation = ResourceCancellation()
        cancellation.cancel()
        let subject = ExportResourceResolver(
            resourceAccess: nil, cancellation: cancellation, unresolvedIsFatal: false
        )
        #expect(throws: CancellationError.self) {
            try subject.disposition(for: "image.png", isImage: true)
        }
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func aggregateQuotaCountsDistinctBytesAndAllowsAliasesAtTheLimit() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("a.png"))
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("b.png"))
        try Data([4]).write(to: directory.appendingPathComponent("c.png"))
        let budget = ExportResourceBudget(
            maxSourceUTF8Bytes: 1024, maxResourceCount: 3, maxSingleResourceBytes: 8,
            maxAggregateResourceBytes: 3, maxDerivedFragmentCount: 8,
            maxAggregateDerivedHTMLBytes: 1024, maxPreparedHTMLUTF8Bytes: 1024
        )
        let subject = try ExportResourceResolver(
            resourceAccess: ExportResourceAccess(openingDirectory: directory),
            unresolvedIsFatal: true, budget: budget
        )
        #expect(try subject.disposition(for: "a.png", isImage: true) != .keep)
        #expect(try subject.disposition(for: "b.png", isImage: true) != .keep)
        #expect(try subject.disposition(for: "c.png", isImage: true) == .keep)
        #expect(subject.frozenManifest().resources.count == 1)
        #expect(subject.diagnostics.count == 1)
        #expect(subject.diagnostics.first?.message.contains("total resource limit") == true)
    }

    @Test func cancellationReachesTheActualCmarkThread() {
        let cancellation = ResourceCancellation()
        let subject = ExportResourceResolver(
            resourceAccess: nil, cancellation: cancellation, unresolvedIsFatal: false
        )
        #expect(throws: CancellationError.self) {
            try CMarkGFM.render("![a](image.png)", options: CMarkGFM.optDefault) { url, isImage in
                cancellation.cancel()
                return try subject.disposition(for: url, isImage: isImage)
            }
        }
        #expect(subject.diagnostics.isEmpty)
    }

    @Test func remoteURLsCannotBecomeDirectoryCapabilities() throws {
        #expect(throws: ResourceReadError.invalidReference) {
            try ExportResourceAccess(openingDirectory: #require(URL(string: "https://example.com/tmp")))
        }
    }
}

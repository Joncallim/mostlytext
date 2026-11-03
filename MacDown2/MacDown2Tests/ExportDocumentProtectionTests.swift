import Darwin
@testable import ExportService
import Foundation
@testable import MacDown2
import Testing

@MainActor
struct ExportDocumentProtectionTests {
    @Test func aLaterOpenOfAnUnchangedDestinationRevokesBeforePublication() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        registry.documentsWillPublish(urls: [fixture.output], identities: [])
        #expect(throws: CancellationError.self) { try fixture.admission.publish(Data("export".utf8), lease: lease) }
        #expect(try Data(contentsOf: fixture.output) == Data("original".utf8))
    }

    @Test func aMissingOpenDocumentReservesItsName() throws {
        let fixture = try fixture(existing: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        registry.documentsWillPublish(urls: [fixture.output], identities: [])
        #expect(throws: CancellationError.self) { try fixture.admission.publish(Data("export".utf8), lease: lease) }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test func aLaterHardLinkOpenAlsoProtectsTheOriginalBytes() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let alias = fixture.root.appendingPathComponent("alias.md")
        try FileManager.default.linkItem(at: fixture.output, to: alias)
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        registry.documentsWillPublish(urls: [alias], identities: [])
        #expect(throws: CancellationError.self) { try lease.withPublicationCutoff {} }
        #expect(try Data(contentsOf: alias) == Data("original".utf8))
    }

    @Test func retainedIdentityProtectsAnUnlinkedLaterDocument() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var info = stat()
        #expect(stat(fixture.output.path, &info) == 0)
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        let vanished = fixture.root.appendingPathComponent("removed-alias.md")
        registry.documentsWillPublish(urls: [vanished], identities: [
            ExportProtectedFileIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: info.st_ino),
        ])
        #expect(throws: CancellationError.self) { try lease.withPublicationCutoff {} }
    }

    @Test func unrelatedDocumentsDoNotCancelTheExport() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let other = fixture.root.appendingPathComponent("other.md")
        try Data("other".utf8).write(to: other)
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        registry.documentsWillPublish(urls: [other], identities: [])
        try fixture.admission.publish(Data("export".utf8), lease: lease)
        #expect(try Data(contentsOf: fixture.output) == Data("export".utf8))
        #expect(try Data(contentsOf: other) == Data("other".utf8))
    }

    @Test func removingACompletedOperationAndExpiredWeakLeasesIsSafe() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        let id = registry.register(fixture.admission, lease: lease)
        registry.remove(id)
        var expired: ExportLifetimeLease? = ExportLifetimeLease()
        weak var observed = expired
        try registry.register(fixture.admission, lease: #require(expired))
        expired = nil
        #expect(observed == nil)
        registry.documentsWillPublish(urls: [fixture.output], identities: [])
        try lease.checkActive()
    }

    @Test func anUnusableDocumentReferenceFailsClosed() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        try registry.documentsWillPublish(urls: [#require(URL(string: "https://example.invalid/a.md"))], identities: [])
        #expect(throws: CancellationError.self) { try lease.checkActive() }
    }

    @Test func aLaterOpenOfARecoveryCandidateRevokesBeforeDocumentPublication() throws {
        let fixture = try fixture(existing: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.root.appendingPathComponent("working.html.tmp")
        try Data("source".utf8).write(to: source)
        var info = stat()
        try #require(stat(source.path, &info) == 0)
        try fixture.admission.checkRecoveryObject(ExportPublicationFilesystem.Stamp(info))
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        registry.documentsWillPublish(urls: [source], identities: [])
        #expect(throws: CancellationError.self) { try lease.checkActive() }
        #expect(throws: ExportError.self) {
            try fixture.admission.checkRecoveryObject(ExportPublicationFilesystem.Stamp(info))
        }
        #expect(try Data(contentsOf: source) == Data("source".utf8))
    }

    @Test func anEarlierDocumentPublicationIsRetainedBeforeCandidateRegistration() throws {
        let fixture = try fixture(existing: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.root.appendingPathComponent("working.html.tmp")
        try Data("source".utf8).write(to: source)
        var info = stat()
        try #require(stat(source.path, &info) == 0)
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        registry.documentsWillPublish(urls: [source], identities: [])
        try lease.checkActive() // unrelated to the primary until recovery registers it
        #expect(throws: ExportError.self) {
            try fixture.admission.checkRecoveryObject(ExportPublicationFilesystem.Stamp(info))
        }
        #expect(try Data(contentsOf: source) == Data("source".utf8))
    }

    @Test func anUnusableURLStillRetainsTheBatchsKnownPhysicalIdentity() throws {
        let fixture = try fixture(existing: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.root.appendingPathComponent("working.html.tmp")
        try Data("source".utf8).write(to: source)
        var info = stat()
        try #require(stat(source.path, &info) == 0)
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        let invalid = try #require(URL(string: "https://example.invalid/document"))
        registry.documentsWillPublish(urls: [invalid], identities: [
            ExportProtectedFileIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino)),
        ])
        #expect(throws: CancellationError.self) { try lease.checkActive() }
        #expect(throws: ExportError.self) {
            try fixture.admission.checkRecoveryObject(ExportPublicationFilesystem.Stamp(info))
        }
        #expect(try Data(contentsOf: source) == Data("source".utf8))
    }

    @Test func aURLConflictStillRetainsAnUnlinkedRecoveryIdentity() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.root.appendingPathComponent("working.html.tmp")
        try Data("source".utf8).write(to: source)
        var info = stat()
        try #require(stat(source.path, &info) == 0)
        let stamp = ExportPublicationFilesystem.Stamp(info)
        try fixture.admission.checkRecoveryObject(stamp)
        let registry = ExportDocumentProtectionRegistry()
        let lease = ExportLifetimeLease()
        registry.register(fixture.admission, lease: lease)
        let vanished = fixture.root.appendingPathComponent("unlinked-source.md")
        registry.documentsWillPublish(urls: [fixture.output, vanished], identities: [
            ExportProtectedFileIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino)),
        ])
        #expect(throws: CancellationError.self) { try lease.checkActive() }
        #expect(throws: ExportError.self) { try fixture.admission.checkRecoveryObject(stamp) }
        #expect(try Data(contentsOf: source) == Data("source".utf8))
    }

    private struct Fixture {
        let root: URL
        let output: URL
        let admission: ExportDestinationAdmission
    }

    private func fixture(existing: Bool = true) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-protection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("output.html")
        if existing {
            try Data("original".utf8).write(to: output)
        }
        return try Fixture(root: root, output: output, admission: ExportDestinationAdmission(capturing: output))
    }
}

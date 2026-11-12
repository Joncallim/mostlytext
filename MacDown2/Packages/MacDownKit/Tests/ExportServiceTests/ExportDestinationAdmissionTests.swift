import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportDestinationAdmissionTests {
    @Test func anAbsentSelectionCannotAdoptAFileCreatedDuringRendering() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let external = Data("later file".utf8)
        try external.write(to: item.primary)
        #expect(throws: ExportError.self) { try admission.publish(Data("export".utf8)) }
        #expect(try Data(contentsOf: item.primary) == external)
        #expect(!FileManager.default.fileExists(atPath: item.assets.path))
    }

    @Test func anExistingSelectionCannotAdoptAnInPlaceEdit() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        try Data("original".utf8).write(to: item.primary)
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let external = Data("an externally edited longer file".utf8)
        try external.write(to: item.primary)
        #expect(throws: ExportError.self) { try admission.publish(Data("export".utf8)) }
        #expect(try Data(contentsOf: item.primary) == external)
    }

    @Test func aReplacedParentCannotRedirectPublication() throws {
        let item = try ExportPublicationTestSupport.fixture()
        let moved = item.directory.appendingPathExtension("moved")
        defer {
            try? FileManager.default.removeItem(at: item.directory)
            try? FileManager.default.removeItem(at: moved)
        }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        try FileManager.default.moveItem(at: item.directory, to: moved)
        try FileManager.default.createDirectory(at: item.directory, withIntermediateDirectories: false)
        #expect(throws: ExportError.self) { try admission.publish(Data([1])) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.directory.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test func unchangedSelectionsPublishAndASecondExportNeedsAFreshAdmission() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        try admission.publish(Data("first".utf8))
        #expect(try Data(contentsOf: item.primary) == Data("first".utf8))
        #expect(throws: ExportError.self) { try admission.publish(Data("stale".utf8)) }
        try ExportDestinationAdmission(capturing: item.primary).publish(Data("second".utf8))
        #expect(try Data(contentsOf: item.primary) == Data("second".utf8))
    }

    @Test func sourceHardLinksCannotBeExportTargets() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let source = item.directory.appendingPathComponent("source.md")
        let original = Data("source fixture".utf8)
        try original.write(to: source)
        try FileManager.default.linkItem(at: source, to: item.primary)
        #expect(throws: ExportError.self) {
            try ExportDestinationAdmission(capturing: item.primary, protecting: [source])
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func anUnlinkedSourceStillProtectsItsObservedObject() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let source = item.directory.appendingPathComponent("source.md")
        try Data("source".utf8).write(to: source)
        var info = stat()
        #expect(lstat(source.path, &info) == 0)
        let identity = ExportProtectedFileIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: info.st_ino)
        try FileManager.default.linkItem(at: source, to: item.primary)
        try FileManager.default.removeItem(at: source)
        let admission = try ExportDestinationAdmission(capturing: item.primary, protecting: [source])
        #expect(throws: ExportError.self) { try admission.checkNoFileAliases([identity]) }
        #expect(try Data(contentsOf: item.primary) == Data("source".utf8))
    }

    @Test func aMissingOpenDocumentStillReservesItsName() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let sameName = item.directory.appendingPathComponent("REPORT.HTML")
        #expect(throws: ExportError.self) {
            try ExportDestinationAdmission(capturing: item.primary, protecting: [sameName])
        }
    }

    @Test func unicodeNameComparisonIsConservative() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let target = item.directory.appendingPathComponent("café.html")
        let source = item.directory.appendingPathComponent("CAFE\u{301}.HTML")
        #expect(throws: ExportError.self) {
            try ExportDestinationAdmission(capturing: target, protecting: [source])
        }
    }

    @Test func anAdmissionCannotBeRetargeted() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        #expect(throws: ExportError.self) {
            try admission.checkTarget(item.directory.appendingPathComponent("other.html"))
        }
    }

    @Test func generatedSnapshotsAreBoundedAndNeverFollowLeafLinks() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let candidate = item.directory.appendingPathComponent("print.tmp.pdf")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: candidate)
        #expect(try admission.readGeneratedFile(at: candidate, maxBytes: 3) == bytes)
        #expect(throws: ExportError.self) { try admission.readGeneratedFile(at: candidate, maxBytes: 2) }
        try FileManager.default.removeItem(at: candidate)
        try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: item.primary)
        #expect(throws: ExportError.self) { try admission.readGeneratedFile(at: candidate, maxBytes: 3) }
    }

    @Test func publicationUsesFrozenBytesWithoutReopeningTheCandidate() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let candidate = item.directory.appendingPathComponent("print.tmp.pdf")
        let original = Data("accepted fixture".utf8)
        try original.write(to: candidate)
        let admitted = try #require(try admission.readGeneratedFile(at: candidate, maxBytes: 64))
        let later = Data("later fixture".utf8)
        try later.write(to: candidate)
        try admission.publish(admitted)
        #expect(try Data(contentsOf: item.primary) == original)
        #expect(try Data(contentsOf: candidate) == later)
    }

    @Test func generatedSnapshotsRejectFIFOsWithoutBlocking() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let candidate = item.directory.appendingPathComponent("print.tmp.pdf")
        #expect(mkfifo(candidate.path, 0o600) == 0)
        #expect(throws: ExportError.self) { try admission.readGeneratedFile(at: candidate, maxBytes: 3) }
    }

    @Test func encodedNULReferencesAreRejectedBeforeFilesystemProjection() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let invalid = try #require(URL(string: item.directory.absoluteString + "/print%00ignored.tmp.pdf"))
        #expect(throws: ExportError.self) { try admission.readGeneratedFile(at: invalid, maxBytes: 3) }
        #expect(throws: ExportError.self) { try ExportDestinationAdmission(capturing: invalid) }
    }

    @Test func revocationPreventsPrimaryDataPublication() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let admission = try ExportDestinationAdmission(capturing: item.primary)
        let lease = ExportLifetimeLease()
        lease.revoke()
        #expect(throws: CancellationError.self) { try admission.publish(Data([1]), lease: lease) }
        #expect(!FileManager.default.fileExists(atPath: item.primary.path))
    }

    @Test func physicalDarwinPrivateTempDirectoryAcceptsGeneratedPDFSnapshot() throws {
        let resolved = try #require(realpath(NSTemporaryDirectory(), nil))
        let parent = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        free(resolved)
        let directory = parent.appendingPathComponent("mostlytext-private-admission-\(UUID().uuidString)",
                                                      isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(chmod(directory.path, 0o700) == 0)
        let destination = directory.appendingPathComponent("export-canary.pdf")
        let generated = directory.appendingPathComponent(".export-canary.print.tmp.pdf")
        let bytes = Data("private PDF bytes".utf8)
        try bytes.write(to: generated)
        let admission = try ExportDestinationAdmission(capturing: destination)
        #expect(try admission.readGeneratedFile(at: generated, maxBytes: 1024) == bytes)
        try admission.publish(bytes)
        #expect(try Data(contentsOf: destination) == bytes)
    }
}

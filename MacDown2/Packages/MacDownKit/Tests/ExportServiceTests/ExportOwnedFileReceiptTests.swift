import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportOwnedFileReceiptTests {
    private typealias Filesystem = ExportPublicationFilesystem

    @Test(arguments: [0, 1, 65536, 65537, 3 * 1024 * 1024])
    func unchangedOwnedScratchRetiresAcrossChunkBoundaries(count: Int) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data(repeating: 0x41, count: count)
        let stamp = try fixture.create(bytes)
        try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor)
        #expect(!FileManager.default.fileExists(atPath: fixture.file.path))
    }

    @Test(arguments: [false, true]) func metadataChangesAfterReceiptCaptureArePreserved(permissions: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data("known scratch bytes".utf8)
        let stamp = try fixture.create(bytes)
        if permissions {
            try #require(chmod(fixture.file.path, 0o400) == 0)
        } else {
            try FileManager.default.setAttributes([
                .modificationDate: Date(timeIntervalSince1970: Double(stamp.modifiedSeconds) + 60),
            ], ofItemAtPath: fixture.file.path)
        }
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
        #expect((try? Data(contentsOf: fixture.file)) == bytes)
    }

    @Test func aChangedPayloadIsPreserved() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let expected = Data("expected".utf8)
        let stamp = try fixture.create(expected)
        try Data("modified".utf8).write(to: fixture.file)
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(expected, name: fixture.name, expected: stamp, in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: fixture.file) == Data("modified".utf8))
    }

    @Test func byteIdenticalReplacementCannotBorrowTheOriginalReceipt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data("same bytes".utf8)
        let stamp = try fixture.create(bytes)
        let retained = fixture.root.appendingPathComponent("original")
        try FileManager.default.moveItem(at: fixture.file, to: retained)
        try bytes.write(to: fixture.file)
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: retained) == bytes)
        #expect(try Data(contentsOf: fixture.file) == bytes)
    }

    @Test func postOpenReplacementIsRefusedWithoutChangingEitherObject() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data("same bytes".utf8)
        let receipt = try ExportOwnedFileReceipt(bytes: bytes, stamp: fixture.create(bytes))
        let retained = fixture.root.appendingPathComponent("original")
        #expect(try !ExportReceiptInspection.verify(receipt, name: fixture.name, in: fixture.descriptor) {
            try FileManager.default.moveItem(at: fixture.file, to: retained)
            try bytes.write(to: fixture.file)
        })
        #expect(try Data(contentsOf: retained) == bytes)
        #expect(try Data(contentsOf: fixture.file) == bytes)
    }

    @Test func postOpenGrowthCannotReadPastItsOneByteProbe() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let receipt = try ExportOwnedFileReceipt(bytes: Data(), stamp: fixture.create(Data()))
        #expect(throws: ExportError.self) {
            try ExportReceiptInspection.verify(receipt, name: fixture.name, in: fixture.descriptor) {
                try Data([1]).write(to: fixture.file)
            }
        }
        #expect(try Data(contentsOf: fixture.file) == Data([1]))
    }

    @Test func aFIFOIsRejectedWithoutWaitingForAWriter() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data([1])
        let stamp = try fixture.create(bytes)
        let receipt = try ExportOwnedFileReceipt(bytes: bytes, stamp: stamp)
        try FileManager.default.removeItem(at: fixture.file)
        try #require(mkfifo(fixture.file.path, 0o600) == 0)
        #expect(try !ExportReceiptInspection.verify(receipt, name: fixture.name, in: fixture.descriptor))
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor)
        }
        #expect(try Filesystem.childStamp(fixture.name, in: fixture.descriptor).kind == mode_t(S_IFIFO))
    }

    @Test func aSymlinkNeverReadsOrDeletesItsTarget() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data([1])
        let stamp = try fixture.create(bytes)
        let outside = fixture.base.appendingPathComponent("outside")
        try bytes.write(to: outside)
        try FileManager.default.removeItem(at: fixture.file)
        try FileManager.default.createSymbolicLink(at: fixture.file, withDestinationURL: outside)
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: outside) == bytes)
        #expect(try Filesystem.childStamp(fixture.name, in: fixture.descriptor).kind == mode_t(S_IFLNK))
    }

    @Test func traversalIsRefusedBeforeTouchingTheOutsideOwnedObject() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let outside = fixture.base.appendingPathComponent("outside")
        let bytes = Data("outside fixture".utf8)
        try bytes.write(to: outside)
        var info = stat()
        try #require(lstat(outside.path, &info) == 0)
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(bytes, name: "../outside", expected: Filesystem.Stamp(info),
                                           in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: outside) == bytes)
    }

    @Test func anOccupiedRestorePreservesBothObjectsAndTheScopedRecoveryPath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data("owned".utf8)
        let stamp = try fixture.create(bytes)
        var retained: URL?
        do {
            try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor) { name in
                do {
                    try Data("changed quarantine".utf8).write(to: fixture.root.appendingPathComponent(name))
                    try Data("new occupant".utf8).write(to: fixture.file)
                } catch { Issue.record(error) }
            }
            Issue.record("Changed occupied quarantine must require recovery")
        } catch let ExportError.publicationRecoveryRequired(url) {
            retained = url
        }
        let quarantine = try #require(retained)
        #expect(quarantine.lastPathComponent.hasPrefix(fixture.prefix))
        #expect(try Data(contentsOf: quarantine) == Data("changed quarantine".utf8))
        #expect(try Data(contentsOf: fixture.file) == Data("new occupant".utf8))
        #expect(throws: ExportError.self) {
            try ExportPublicationRetention.checkParent(fixture.descriptor, scratchPrefix: fixture.prefix)
        }
    }

    @Test func postQuarantineExtendedMetadataIsPreservedWithThePayload() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data("owned".utf8)
        let annotation = Data("private fixture annotation".utf8)
        let key = "com.mostlytext.receipt-test"
        let stamp = try fixture.create(bytes)
        #expect(throws: ExportError.self) {
            try Filesystem.retireTemporary(bytes, name: fixture.name, expected: stamp, in: fixture.descriptor) { name in
                let url = fixture.root.appendingPathComponent(name)
                let result = annotation.withUnsafeBytes {
                    setxattr(url.path, key, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
                }
                #expect(result == 0)
            }
        }
        #expect((try? Data(contentsOf: fixture.file)) == bytes)
        var actual = [UInt8](repeating: 0, count: annotation.count)
        let count = getxattr(fixture.file.path, key, &actual, actual.count, 0, XATTR_NOFOLLOW)
        #expect(count == annotation.count)
        #expect(Data(actual) == annotation)
    }

    @Test func cancellationStillCleansExactlyTheKnownOwnedScratch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bytes = Data(repeating: 1, count: 65537)
        _ = try fixture.create(bytes)
        let descriptor = fixture.descriptor
        let name = fixture.name
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let stamp = try Filesystem.childStamp(name, in: descriptor)
            try Filesystem.retireTemporary(bytes, name: name, expected: stamp, in: descriptor)
        }
        try await operation.value
        #expect(!FileManager.default.fileExists(atPath: fixture.file.path))
    }

    private final class Fixture {
        let base: URL
        let root: URL
        let prefix = ".mt-" + String(repeating: "a", count: 64) + "-"
        let directory: Filesystem.DirectoryHandle
        var name: String {
            prefix + "fixture.stage"
        }

        var file: URL {
            root.appendingPathComponent(name)
        }

        var descriptor: Int32 {
            directory.descriptor
        }

        init() throws {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("export-receipt-\(UUID().uuidString)")
            root = base.appendingPathComponent("root")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw Filesystem.posixFailure() }
            directory = Filesystem.DirectoryHandle(descriptor)
        }

        func create(_ bytes: Data) throws -> Filesystem.Stamp {
            try bytes.write(to: file)
            return try Filesystem.childStamp(name, in: descriptor)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: base)
        }
    }
}

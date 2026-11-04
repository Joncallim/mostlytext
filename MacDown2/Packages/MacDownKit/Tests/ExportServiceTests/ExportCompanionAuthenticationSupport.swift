import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

final class ExportCompanionAuthenticationFixture {
    let root: URL
    let directory: ExportPublicationFilesystem.DirectoryHandle
    let directoryStamp: ExportPublicationFilesystem.Stamp
    let binding: ExportJournalRecord.Binding
    let key = Data(repeating: 0x4D, count: 32)
    let metadataBeforeWrite: ExportPublicationFilesystem.Stamp
    let entry: ExportCompanionInventoryRecord.Entry
    private let metadataDescriptor: Int32

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MostlyText-Companion-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let parent = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw ExportError.unsafePublication }
        defer { Darwin.close(parent) }
        binding = try ExportJournalRecord.Binding(parent: ExportPublicationFilesystem.directoryStamp(parent),
                                                  leaf: "report.html")
        guard mkdirat(parent, "report.assets", 0o700) == 0 else { throw ExportError.unsafePublication }
        let descriptor = openat(parent, "report.assets", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.unsafePublication }
        directory = ExportPublicationFilesystem.DirectoryHandle(descriptor)
        directoryStamp = try ExportPublicationFilesystem.directoryStamp(descriptor)
        let name = ExportCompanionInventoryRecord.fileName
        metadataDescriptor = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard metadataDescriptor >= 0 else { throw ExportError.unsafePublication }
        metadataBeforeWrite = try Self.stamp(metadataDescriptor)
        let bytes = Data("fixture image bytes".utf8)
        let resource = ExportResourceIdentity(bytes: bytes, mimeType: "image/png")
        let path = root.appendingPathComponent("report.assets").appendingPathComponent(resource.fileName)
        try bytes.write(to: path, options: .withoutOverwriting)
        let stamp = try ExportPublicationFilesystem.childStamp(resource.fileName, in: descriptor)
        entry = try .init(name: resource.fileName, mimeType: resource.mimeType,
                          receipt: ExportJournalRecord.Receipt(ExportOwnedFileReceipt(bytes: bytes, stamp: stamp)))
    }

    deinit {
        Darwin.close(metadataDescriptor)
        try? FileManager.default.removeItem(at: root)
    }

    func codec(keyBytes: Data? = nil, binding: ExportJournalRecord.Binding? = nil) throws
        -> ExportCompanionAuthentication {
        try ExportCompanionAuthentication(keyBytes: keyBytes ?? key, binding: binding ?? self.binding)
    }

    func bindingForLeaf(_ leaf: String) throws -> ExportJournalRecord.Binding {
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.unsafePublication }
        defer { Darwin.close(descriptor) }
        return try ExportJournalRecord.Binding(
            parent: ExportPublicationFilesystem.directoryStamp(descriptor), leaf: leaf
        )
    }

    func record(required: [String]? = nil, owned: [ExportCompanionInventoryRecord.Entry]? = nil,
                primary: Data? = Data(repeating: 1, count: 32), referencesKnown: Bool = true)
        -> ExportCompanionInventoryRecord {
        ExportCompanionInventoryRecord(
            binding: binding, directory: directoryStamp, metadata: metadataBeforeWrite,
            primaryDigest: primary, referencesKnown: referencesKnown,
            requiredNames: required ?? [entry.name], owned: owned ?? [entry]
        )
    }

    func writeMetadata(_ bytes: Data) throws -> ExportPublicationFilesystem.Stamp {
        guard ftruncate(metadataDescriptor, 0) == 0, lseek(metadataDescriptor, 0, SEEK_SET) == 0 else {
            throw ExportError.unsafePublication
        }
        var progress = 0
        try ExportPublicationFilesystem.writeAll(bytes, to: metadataDescriptor, progress: &progress)
        guard fsync(metadataDescriptor) == 0 else { throw ExportError.unsafePublication }
        return try Self.stamp(metadataDescriptor)
    }

    func rawEnvelope(payload: Data, domain: String = "MostlyText.Export.CompanionInventory.v1\0") throws -> Data {
        struct Envelope: Encodable {
            let payload: Data
            let authentication: Data
        }
        let authentication = HMAC<SHA256>.authenticationCode(
            for: Data(domain.utf8) + payload, using: SymmetricKey(data: key)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(payload: payload, authentication: Data(authentication)))
    }

    static func stamp(_ descriptor: Int32) throws -> ExportPublicationFilesystem.Stamp {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw ExportError.unsafePublication }
        return ExportPublicationFilesystem.Stamp(value)
    }
}

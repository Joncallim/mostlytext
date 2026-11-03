import CryptoKit
import Darwin
import Foundation

/// Authentication is granted by this loader, never by decoding a public marker
/// or an archived receipt on its own. A stable flock covers the entire writer.
final class ExportJournalStore {
    static let maximumBytes = 64 * 1024

    struct AuthenticatedReceipt {
        let value: ExportJournalRecord.Receipt
        fileprivate init(_ value: ExportJournalRecord.Receipt) {
            self.value = value
        }
    }

    private struct Envelope: Codable {
        let payload: Data
        let authentication: Data
    }

    private typealias Filesystem = ExportPublicationFilesystem
    private let directory: Filesystem.DirectoryHandle
    private let lock: Filesystem.DirectoryHandle
    private let location: ExportRecoveryLocation
    private let directoryStamp: Filesystem.Stamp
    private let keyBytes: Data
    private let binding: ExportJournalRecord.Binding
    private let fileName: String
    private var previous: Data?
    private var writtenReceipt: ExportOwnedFileReceipt?
    private(set) var record: ExportJournalRecord

    init(location: ExportRecoveryLocation, parent: ExportPublicationFilesystem.Stamp, leaf: String) throws {
        self.location = location
        directory = try ExportJournalStorage.open(location)
        directoryStamp = try Filesystem.directoryStamp(directory.descriptor)
        guard !directoryStamp.sameDirectory(as: parent),
              let key = try ExportJournalStorage.read("producer.key", in: directory.descriptor, maximum: 32),
              key.count == 32 else { throw ExportError.unsafePublication }
        keyBytes = key
        lock = try ExportJournalStorage.lock(directory.descriptor)
        try ExportJournalStorage.checkCount(directory.descriptor)
        guard try ExportJournalStorage.read("producer.key", in: directory.descriptor, maximum: 32) == key
        else { throw ExportError.unsafePublication }
        binding = ExportJournalRecord.Binding(parent: parent, leaf: leaf)
        fileName = try binding.fileName
        previous = try ExportJournalStorage.read(fileName, in: directory.descriptor, maximum: Self.maximumBytes)
        if let previous {
            // Verify before decoding any filesystem identities or receipt fields.
            let envelope = try JSONDecoder().decode(Envelope.self, from: previous)
            guard envelope.payload.count <= Self.maximumBytes / 2,
                  HMAC<SHA256>.isValidAuthenticationCode(envelope.authentication,
                                                         authenticating: Self.message(envelope.payload),
                                                         using: SymmetricKey(data: key))
            else { throw ExportError.unsafePublication }
            record = try JSONDecoder().decode(ExportJournalRecord.self, from: envelope.payload)
        } else {
            record = ExportJournalRecord(binding: binding)
        }
        try validate(record)
    }

    func begin(priorDigest: Data?, desired: Data, name: String, receipt: ExportOwnedFileReceipt) throws {
        guard record.pending == nil else { throw ExportError.unsafePublication }
        let prefix = try scratchPrefix
        let suffix = String(name.dropFirst(prefix.count).dropLast(".html.tmp".count))
        guard let operation = UUID(uuidString: suffix), name == prefix + operation.uuidString + ".html.tmp"
        else { throw ExportError.unsafePublication }
        var next = record
        next.pending = .init(operation: operation, priorDigest: priorDigest, desiredDigest: desired,
                             scratch: name, receipt: .init(receipt))
        try save(next)
    }

    func prepareQuarantine() throws -> String {
        guard var pending = record.pending else { throw ExportError.unsafePublication }
        if let existing = pending.quarantine {
            return existing
        }
        let prefix = try scratchPrefix
        let name = prefix + UUID().uuidString + ".retired"
        pending.quarantine = name
        var next = record
        next.pending = pending
        try save(next)
        return name
    }

    func ownedReceipt() throws -> ExportOwnedFileReceipt {
        try checkCurrent()
        guard let pending = record.pending else { throw ExportError.unsafePublication }
        return try ExportOwnedFileReceipt(authenticated: AuthenticatedReceipt(pending.receipt))
    }

    func finish() throws {
        try save(ExportJournalRecord(binding: binding))
        // The durable idle checkpoint grants no output deletion authority.
        // Retire our exclusively written checkpoint so successful exports to
        // distinct names do not accumulate a private lifetime output limit.
        guard let writtenReceipt else { throw ExportError.unsafePublication }
        try checkCurrent()
        try ExportFileRetirement.retire(writtenReceipt, name: fileName, in: directory.descriptor)
        guard fsync(directory.descriptor) == 0 else { throw Filesystem.posixFailure() }
        previous = nil
        self.writtenReceipt = nil
    }

    private func save(_ next: ExportJournalRecord) throws {
        try validate(next)
        try checkCurrent()
        try ExportJournalStorage.checkCount(directory.descriptor)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(next)
        guard payload.count <= Self.maximumBytes / 2 else { throw ExportError.unsafePublication }
        let code = HMAC<SHA256>.authenticationCode(for: Self.message(payload), using: SymmetricKey(data: keyBytes))
        let bytes = try encoder.encode(Envelope(payload: payload, authentication: Data(code)))
        guard bytes.count <= Self.maximumBytes else { throw ExportError.unsafePublication }
        let stamp = try ExportJournalStorage.replace(
            bytes,
            named: fileName,
            previous: previous,
            in: directory.descriptor
        )
        writtenReceipt = try ExportOwnedFileReceipt(bytes: bytes, stamp: stamp)
        previous = bytes
        record = next
    }

    func checkCurrent() throws {
        try ExportJournalStorage.checkAuthority(directory: directory.descriptor, lock: lock.descriptor)
        guard try Filesystem.directoryAtPath(location.directory.path, matches: directoryStamp),
              try ExportJournalStorage.read("producer.key", in: directory.descriptor, maximum: 32) == keyBytes
        else { throw ExportError.unsafePublication }
    }

    private func validate(_ candidate: ExportJournalRecord) throws {
        guard candidate.schema == 1, candidate.binding == binding else { throw ExportError.unsafePublication }
        guard let pending = candidate.pending else { return }
        let prefix = try scratchPrefix
        guard pending.scratch == prefix + pending.operation.uuidString + ".html.tmp",
              pending.desiredDigest.count == SHA256.byteCount,
              pending.priorDigest == nil || pending.priorDigest?.count == SHA256.byteCount,
              pending.receipt.digest == pending.desiredDigest,
              pending.receipt.stamp.kind == mode_t(S_IFREG), pending.receipt.stamp.size >= 0,
              pending.receipt.stamp.size <= ExportResourceBudget.maxFinalHTMLUTF8Bytes,
              pending.receipt.stamp.owner == geteuid(), pending.receipt.stamp.links == 1
        else { throw ExportError.unsafePublication }
        if let quarantine = pending.quarantine {
            guard quarantine.hasPrefix(prefix), quarantine.hasSuffix(".retired"),
                  UUID(uuidString: String(quarantine.dropFirst(prefix.count).dropLast(".retired".count))) != nil
            else { throw ExportError.unsafePublication }
        }
    }

    private var scratchPrefix: String {
        get throws {
            guard let leaf = String(bytes: binding.leaf, encoding: .utf8) else { throw ExportError.unsafePublication }
            return ExportPublicationRetention.scratchPrefix(for: leaf)
        }
    }

    private static func message(_ payload: Data) -> Data {
        // A distinct domain/version prevents other local uses of the same key
        // from producing a valid export record. The full payload is authenticated.
        Data("MostlyText.Export.PrimaryJournal.v1\0".utf8) + payload
    }
}

import CryptoKit
import Darwin
import Foundation

enum ExportCompanionLimits {
    static let payloadBytes = 512 * 1024
    static let envelopeBytes = 1024 * 1024
    static let privateBytes = 64 * 1024 * 1024
    static let ownedEntries = ExportResourceBudget.standard.maxResourceCount * 2
}

/// Stable object identity survives our rename, but rejects an otherwise
/// byte-identical copy. Mutation timestamps belong to each concrete receipt.
struct ExportCompanionObjectIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let birthSeconds: Int64
    let birthNanoseconds: Int64
    let kind: mode_t
    let owner: uid_t
    let group: gid_t
    let permissions: mode_t
    let links: nlink_t
    let flags: UInt32

    init(_ stamp: ExportPublicationFilesystem.Stamp) {
        device = stamp.device
        inode = stamp.inode
        birthSeconds = stamp.birthSeconds
        birthNanoseconds = stamp.birthNanoseconds
        kind = stamp.kind
        owner = stamp.owner
        group = stamp.group
        permissions = stamp.permissions
        links = stamp.links
        flags = stamp.flags
    }

    func sameDirectory(as stamp: ExportPublicationFilesystem.Stamp) -> Bool {
        kind == mode_t(S_IFDIR) && stamp.kind == kind
            && device == stamp.device && inode == stamp.inode
            && birthSeconds == stamp.birthSeconds && birthNanoseconds == stamp.birthNanoseconds
    }

    func sameFile(as stamp: ExportPublicationFilesystem.Stamp) -> Bool {
        kind == mode_t(S_IFREG) && stamp.kind == kind
            && self == Self(stamp)
    }

    var validBirthTime: Bool {
        (0 ..< 1_000_000_000).contains(birthNanoseconds)
    }
}

/// The payload is not removal authority. Only a verified producer envelope,
/// matching its actual metadata inode and directory, can restore receipts.
struct ExportCompanionInventoryRecord: Codable {
    struct Entry: Codable {
        let name: String
        let mimeType: String
        let receipt: ExportJournalRecord.Receipt
    }

    static let fileName = ".mostlytext-export-inventory.json"
    let schema: Int
    let binding: ExportJournalRecord.Binding
    let directory: ExportCompanionObjectIdentity
    let metadata: ExportCompanionObjectIdentity
    let primaryDigest: Data?
    let referencesKnown: Bool
    let requiredNames: [String]
    let owned: [Entry]

    init(binding: ExportJournalRecord.Binding, directory: ExportPublicationFilesystem.Stamp,
         metadata: ExportPublicationFilesystem.Stamp, primaryDigest: Data?,
         referencesKnown: Bool, requiredNames: [String], owned: [Entry]) {
        schema = 1
        self.binding = binding
        self.directory = ExportCompanionObjectIdentity(directory)
        self.metadata = ExportCompanionObjectIdentity(metadata)
        self.primaryDigest = primaryDigest
        self.referencesKnown = referencesKnown
        self.requiredNames = requiredNames
        self.owned = owned
    }

    func validate(binding expected: ExportJournalRecord.Binding) throws {
        guard schema == 1, binding == expected,
              directory.kind == mode_t(S_IFDIR),
              directory.validBirthTime, metadata.validBirthTime, metadata.device == directory.device,
              metadata.kind == mode_t(S_IFREG), metadata.owner == geteuid(), metadata.links == 1,
              metadata.permissions == 0o600,
              primaryDigest == nil || primaryDigest?.count == SHA256.byteCount,
              requiredNames.count <= ExportResourceBudget.standard.maxResourceCount,
              owned.count <= ExportCompanionLimits.ownedEntries,
              referencesKnown || requiredNames.isEmpty,
              primaryDigest != nil || (referencesKnown && requiredNames.isEmpty)
        else { throw ExportError.unsafePublication }
        var names = Set<String>()
        for name in requiredNames {
            guard Self.isResourceName(name), names.insert(name).inserted else { throw ExportError.unsafePublication }
        }
        names.removeAll(keepingCapacity: true)
        var objects = Set<String>()
        for entry in owned {
            let stamp = entry.receipt.stamp
            let digest = entry.receipt.digest
            guard digest.count == SHA256.byteCount else { throw ExportError.unsafePublication }
            let prefix = digest.map { String(format: "%02x", $0) }.joined() + "."
            let object = "\(stamp.device):\(stamp.inode):\(stamp.birthSeconds):\(stamp.birthNanoseconds)"
            guard Self.isResourceName(entry.name), entry.name.hasPrefix(prefix),
                  names.insert(entry.name).inserted, objects.insert(object).inserted,
                  stamp.kind == mode_t(S_IFREG), stamp.device == directory.device,
                  (0 ..< 1_000_000_000).contains(stamp.birthNanoseconds),
                  stamp.owner == geteuid(), stamp.links == 1, stamp.size >= 0,
                  stamp.size <= ExportResourceBudget.standard.maxSingleResourceBytes,
                  !metadata.sameFile(as: stamp),
                  !entry.mimeType.isEmpty, entry.mimeType.utf8.count <= 128,
                  !entry.mimeType.utf8.contains(0)
            else { throw ExportError.unsafePublication }
        }
    }

    static func isResourceName(_ name: String) -> Bool {
        let units = Array(name.utf8)
        guard units.count > 65, units.count <= 128, units[64] == UInt8(ascii: ".") else { return false }
        return units.prefix(64).allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
            && units.dropFirst(65).allSatisfy {
                (48 ... 57).contains($0) || (97 ... 122).contains($0) || $0 == 45
            }
    }
}

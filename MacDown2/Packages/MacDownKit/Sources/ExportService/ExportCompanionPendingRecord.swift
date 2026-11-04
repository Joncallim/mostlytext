import CryptoKit
import Darwin
import Foundation

/// A durable intent precedes every public mutation. This model grants no
/// removal capability until its private producer envelope has been verified.
struct ExportCompanionPendingRecord: Codable {
    enum Phase: String, Codable {
        case preparing
        case committed
        case aborted
    }

    enum FileRole: String, Codable {
        case resource
        case marker
        case inventory
    }

    struct WorkFile: Codable {
        let name: String
        let temporary: String
        let role: FileRole
        let mimeType: String?
        var receipt: ExportJournalRecord.Receipt?
    }

    struct Retirement: Codable {
        let name: String
        let quarantine: String
        let receipt: ExportJournalRecord.Receipt
    }

    let schema: Int
    let binding: ExportJournalRecord.Binding
    let operation: UUID
    let assetsName: String
    let createdDirectory: Bool
    let priorDigest: Data?
    let desiredDigest: Data
    let priorReferencesKnown: Bool
    let priorRequiredNames: [String]
    let desiredReferencesKnown: Bool
    let retireObsoleteResources: Bool
    let requiredNames: [String]
    var phase: Phase
    var inventoryPublished: Bool
    var publishedOwnedCount: Int
    var directory: ExportCompanionObjectIdentity?
    var previousInventory: ExportJournalRecord.Receipt?
    var owned: [ExportCompanionInventoryRecord.Entry]
    var createdNames: [String]
    var files: [WorkFile]
    var retirements: [Retirement]

    init(binding: ExportJournalRecord.Binding, assetsName: String, priorDigest: Data?, desiredDigest: Data,
         priorReferencesKnown: Bool, priorRequiredNames: [String], desiredReferencesKnown: Bool,
         requiredNames: [String], retireObsoleteResources: Bool = true, createdDirectory: Bool = false) {
        schema = 1
        self.binding = binding
        operation = UUID()
        self.assetsName = assetsName
        self.createdDirectory = createdDirectory
        self.priorDigest = priorDigest
        self.desiredDigest = desiredDigest
        self.priorReferencesKnown = priorReferencesKnown
        self.priorRequiredNames = priorRequiredNames
        self.desiredReferencesKnown = desiredReferencesKnown
        self.retireObsoleteResources = retireObsoleteResources
        self.requiredNames = requiredNames
        phase = .preparing
        inventoryPublished = false
        publishedOwnedCount = 0
        owned = []
        createdNames = []
        files = []
        retirements = []
    }

    var temporaryPrefix: String {
        ".mt-companion-" + operation.uuidString + "-"
    }

    func temporaryName(suffix: String) -> String {
        temporaryPrefix + UUID().uuidString + suffix
    }

    func validate(binding expected: ExportJournalRecord.Binding) throws {
        guard schema == 1, binding == expected,
              let leaf = String(bytes: binding.leaf, encoding: .utf8), safeComponent(leaf),
              assetsName.utf8.elementsEqual(ExportHTMLWriter.assetsDirectoryName(
                  for: URL(fileURLWithPath: "/").appendingPathComponent(leaf)
              ).utf8),
              desiredDigest.count == SHA256.byteCount,
              priorDigest == nil || priorDigest?.count == SHA256.byteCount,
              priorReferencesKnown || priorRequiredNames.isEmpty,
              priorDigest != nil || (priorReferencesKnown && priorRequiredNames.isEmpty),
              validResourceNames(requiredNames), validResourceNames(priorRequiredNames),
              validResourceNames(createdNames), Set(createdNames).isSubset(of: Set(requiredNames)),
              owned.count <= ExportCompanionLimits.ownedEntries,
              (0 ... ExportCompanionLimits.ownedEntries).contains(publishedOwnedCount),
              inventoryPublished || publishedOwnedCount == 0,
              !inventoryPublished || previousInventory != nil,
              files.count <= ExportResourceBudget.standard.maxResourceCount + 2,
              retirements.count <= ExportCompanionLimits.ownedEntries + 2
        else { throw ExportError.unsafePublication }
        guard let directory else {
            guard owned.isEmpty, createdNames.isEmpty, files.isEmpty, retirements.isEmpty, previousInventory == nil,
                  phase == .preparing, !inventoryPublished,
                  publishedOwnedCount == 0 else { throw ExportError.unsafePublication }
            return
        }
        guard directory.kind == mode_t(S_IFDIR), directory.validBirthTime else {
            throw ExportError.unsafePublication
        }
        if let previousInventory {
            try validateReceipt(previousInventory, device: directory.device,
                                maximum: ExportCompanionLimits.envelopeBytes)
        }
        try validateOwned(device: directory.device)
        try validateWorkFiles(device: directory.device)
        var names = Set<String>()
        var quarantines = Set<String>()
        for item in retirements {
            guard safeWorkingName(item.name), validTemporary(item.quarantine, suffix: ".retired"),
                  names.insert(item.name).inserted, quarantines.insert(item.quarantine).inserted,
                  !names.contains(item.quarantine), !quarantines.contains(item.name)
            else { throw ExportError.unsafePublication }
            try validateReceipt(item.receipt, device: directory.device,
                                maximum: ExportResourceBudget.standard.maxSingleResourceBytes)
        }
    }

    private func validateOwned(device: UInt64) throws {
        var names = Set<String>()
        var objects = Set<String>()
        for entry in owned {
            guard ExportCompanionInventoryRecord.isResourceName(entry.name),
                  names.insert(entry.name).inserted,
                  digestMatchesName(entry.receipt.digest, name: entry.name), validMIME(entry.mimeType),
                  objects.insert(objectKey(entry.receipt.stamp)).inserted
            else { throw ExportError.unsafePublication }
            try validateReceipt(entry.receipt, device: device,
                                maximum: ExportResourceBudget.standard.maxSingleResourceBytes)
        }
    }

    private func validateWorkFiles(device: UInt64) throws {
        var names = Set<String>()
        var temporaryNames = Set<String>()
        var objects = Set<String>()
        for file in files {
            guard names.insert(file.name).inserted, temporaryNames.insert(file.temporary).inserted,
                  validTemporary(file.temporary, suffix: ".stage") else { throw ExportError.unsafePublication }
            switch file.role {
            case .resource:
                guard ExportCompanionInventoryRecord.isResourceName(file.name),
                      let mimeType = file.mimeType, validMIME(mimeType), requiredNames.contains(file.name)
                else { throw ExportError.unsafePublication }
            case .marker:
                guard file.name == ExportFileWriter.markerFileName, file.mimeType == nil
                else { throw ExportError.unsafePublication }
            case .inventory:
                guard file.name == ExportCompanionInventoryRecord.fileName, file.mimeType == nil
                else { throw ExportError.unsafePublication }
            }
            if let receipt = file.receipt {
                try validateReceipt(receipt, device: device, maximum: file.role == .inventory
                    ? ExportCompanionLimits.envelopeBytes
                    : ExportResourceBudget.standard.maxSingleResourceBytes)
                guard objects.insert(objectKey(receipt.stamp)).inserted,
                      file.role != .resource || digestMatchesName(receipt.digest, name: file.name)
                else { throw ExportError.unsafePublication }
            }
        }
    }

    private func validateReceipt(_ receipt: ExportJournalRecord.Receipt, device: UInt64, maximum: Int) throws {
        let stamp = receipt.stamp
        guard receipt.digest.count == SHA256.byteCount, stamp.kind == mode_t(S_IFREG), stamp.device == device,
              stamp.size >= 0, stamp.size <= maximum, stamp.owner == geteuid(), stamp.links == 1,
              (0 ..< 1_000_000_000).contains(stamp.birthNanoseconds)
        else { throw ExportError.unsafePublication }
    }

    private func validResourceNames(_ names: [String]) -> Bool {
        names.count <= ExportResourceBudget.standard.maxResourceCount
            && Set(names).count == names.count && names.allSatisfy(ExportCompanionInventoryRecord.isResourceName)
    }

    private func validTemporary(_ name: String, suffix: String) -> Bool {
        guard name.hasPrefix(temporaryPrefix), name.hasSuffix(suffix) else { return false }
        let middle = String(name.dropFirst(temporaryPrefix.count).dropLast(suffix.count))
        return UUID(uuidString: middle)?.uuidString == middle
    }

    private func safeWorkingName(_ name: String) -> Bool {
        ExportCompanionInventoryRecord.isResourceName(name) || name == ExportFileWriter.markerFileName
            || name == ExportCompanionInventoryRecord.fileName || validTemporary(name, suffix: ".stage")
    }

    private func safeComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.utf8.contains(0)
            && !name.utf8.contains(UInt8(ascii: "/"))
    }

    private func validMIME(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && !value.utf8.contains(0)
    }

    private func digestMatchesName(_ digest: Data, name: String) -> Bool {
        digest.count == SHA256.byteCount && name.hasPrefix(digest.map { String(format: "%02x", $0) }.joined() + ".")
    }

    private func objectKey(_ stamp: ExportPublicationFilesystem.Stamp) -> String {
        "\(stamp.device):\(stamp.inode):\(stamp.birthSeconds):\(stamp.birthNanoseconds)"
    }
}

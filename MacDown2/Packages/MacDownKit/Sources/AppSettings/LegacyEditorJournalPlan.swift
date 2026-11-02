import CryptoKit
import Foundation
import JSONSupport

public enum LegacyMigrationFailure: Error, Sendable, Equatable {
    case unsafeStorage
    case changedStorage
    case unavailable(Int32)
    case invalidRecord
    case transactionExists
    case invalidPhase
    case unboundDestination
    case busy
}

struct LegacyEditorJournalPlan: Codable, Sendable, Equatable {
    let version: Int
    let mappingVersion: Int
    let id: UUID
    let domain: String
    let sourceDigest: String
    let before: Data?
    let desired: Data
    let selected: [String]
    let fontPostScriptName: String?

    init(proposal: LegacyEditorWriteProposal, domain: String, before: Data?) throws {
        version = 1; mappingVersion = proposal.mappingVersion; id = UUID()
        self.domain = domain; sourceDigest = proposal.sourceDigest
        self.before = before; desired = proposal.desiredData
        selected = proposal.selected.map(\.rawValue).sorted()
        fontPostScriptName = proposal.fontPostScriptName
        guard LegacyEditorDestinationEvidence.decode(before).rawRevision == proposal.beforeRevision else {
            throw LegacyMigrationFailure.invalidRecord
        }
        _ = try restoredProposal()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= MigrationJournalDirectory.maximumBytes else { throw LegacyMigrationFailure.invalidRecord }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> Self {
        try validateJSON(bytes)
        let plan = try JSONDecoder().decode(Self.self, from: bytes)
        guard try plan.encoded() == bytes else { throw LegacyMigrationFailure.invalidRecord }
        _ = try plan.restoredProposal()
        return plan
    }

    func restoredProposal() throws -> LegacyEditorWriteProposal {
        guard version == 1, mappingVersion == 1 || mappingVersion == 2,
              (mappingVersion == 2) == (fontPostScriptName != nil),
              UserDefaultsAppSettingsStore.admitsPersistenceDomain(domain),
              desired.count <= 65536, (before?.count ?? 0) <= 65536,
              sourceDigest.utf8.count == 64,
              sourceDigest.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }),
              !selected.isEmpty || fontPostScriptName != nil, selected.count <= 3,
              selected == Array(Set(selected)).sorted()
        else { throw LegacyMigrationFailure.invalidRecord }
        let fields = selected.compactMap(LegacyImportPlan.Destination.init(rawValue:))
        guard fields.count == selected.count else { throw LegacyMigrationFailure.invalidRecord }
        return try LegacyEditorWriteProposal(restoring: self, selected: Set(fields))
    }

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func validateJSON(_ bytes: Data) throws {
        guard bytes.count <= MigrationJournalDirectory.maximumBytes,
              let text = String(data: bytes, encoding: .utf8),
              case .valid = JSONParser.parse(text) else { throw LegacyMigrationFailure.invalidRecord }
    }
}

extension LegacyEditorWriteProposal {
    init(restoring record: LegacyEditorJournalPlan, selected: Set<Destination>) throws {
        let before = LegacyEditorDestinationEvidence.decode(record.before)
        let after = LegacyEditorDestinationEvidence.decode(record.desired)
        guard before.status == .absent || before.settings != nil,
              let desired = after.settings else { throw LegacyMigrationFailure.invalidRecord }
        var allowed = before.settings ?? .default
        if let name = record.fontPostScriptName {
            guard !name.isEmpty, name.utf8.count <= 4096,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw LegacyMigrationFailure.invalidRecord }
            allowed.font = desired.font
        }
        for field in selected {
            switch field {
            case .smartHome: allowed.smartHome = desired.smartHome
            case .convertsTabsToSpaces: allowed.convertsTabsToSpaces = desired.convertsTabsToSpaces
            case .autoIncrementOrderedLists: allowed.autoIncrementOrderedLists = desired.autoIncrementOrderedLists
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(allowed) == record.desired, try encoder.encode(desired) == record.desired else {
            throw LegacyMigrationFailure.invalidRecord
        }
        mappingVersion = record.mappingVersion
        fontPostScriptName = record.fontPostScriptName
        sourceDigest = record.sourceDigest
        beforeRevision = before.rawRevision
        desiredRevision = after.rawRevision
        desiredData = record.desired
        self.selected = selected
    }

    func matchesJournalSource(_ source: LegacyPreferenceSnapshot) -> Bool {
        guard source.canonicalDigest == sourceDigest,
              let desired = LegacyEditorDestinationEvidence.decode(desiredData).settings else { return false }
        if let name = fontPostScriptName {
            guard LegacyPreferenceReport(snapshot: source).entries.contains(where: {
                guard case let .requiresExactInstalledFont(request) = $0.disposition else { return false }
                return request.postScriptName.utf8.elementsEqual(name.utf8) && request.size == desired.font.size
            }) else { return false }
        }
        let converted = LegacyEditorBooleanConversion(snapshot: source).proposedValues
        return selected.allSatisfy { field in
            switch field {
            case .smartHome: converted[field] == desired.smartHome
            case .convertsTabsToSpaces: converted[field] == desired.convertsTabsToSpaces
            case .autoIncrementOrderedLists: converted[field] == desired.autoIncrementOrderedLists
            }
        }
    }
}

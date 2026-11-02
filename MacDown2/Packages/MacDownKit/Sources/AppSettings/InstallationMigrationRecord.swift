import Foundation

struct InstallationMigrationRecord: Codable, Sendable {
    let version: Int
    let id: UUID
    let sourcePaths: [String]
    let destinationDomains: [String]
    let trees: [InstallationTreeSnapshot]
    let sourcePreferenceDigests: [String]
    let beforePreferenceDigests: [String]
    let adoptsDevelopment: Bool
    let completedOriginalImport: Bool

    func encoded() throws -> Data {
        let entries = trees.flatMap(\.entries)
        guard entries.count <= InstallationTree.maximumEntries,
              entries
              .allSatisfy({
                  $0.identity.size >= 0 && ($0.directory || $0.identity.size <= InstallationTree.maximumFileBytes) }),
              entries.filter({ !$0.directory }).reduce(Int64(0), { $0 + $1.identity.size }) <= InstallationTree
              .maximumTotalBytes
        else { throw LegacyMigrationFailure.invalidRecord }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= MigrationJournalDirectory.maximumBytes else { throw LegacyMigrationFailure.invalidRecord }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> Self {
        try LegacyEditorJournalPlan.validateJSON(bytes)
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.version == 1, value.sourcePaths.count == 3, value.trees.count == 3,
              value.destinationDomains.count == 2, value.sourcePreferenceDigests.count == 2,
              value.beforePreferenceDigests.count == 2, try value.encoded() == bytes else {
            throw LegacyMigrationFailure.invalidRecord
        }
        return value
    }
}

public struct PreparedInstallationMigration: Sendable {
    public let locations: ApplicationStorageLocations
    public let desiredPreferences: InstallationPreferences
    public let beforePreferenceDigests: [String]
    public let sourcePreferenceDigests: [String]
    public let isComplete: Bool
    public let preferencesAcknowledged: Bool
    public let adoptsDevelopment: Bool
    public let completedOriginalImport: Bool
    public let hasPreservedDevelopmentState: Bool
    let owner: UUID
    let recordID: UUID
    let stageName: String?
}

struct InstallationMigrationMarker: Codable {
    let version: Int
    let digest: String
    let phase: String

    init(record: InstallationMigrationRecord, phase: String) throws {
        version = 1; digest = try LegacyEditorJournalPlan.digest(record.encoded()); self.phase = phase
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func validate(_ bytes: Data, record: InstallationMigrationRecord, phase: String) throws {
        let expected = try Self(record: record, phase: phase).encoded()
        guard bytes == expected else { throw LegacyMigrationFailure.invalidRecord }
    }
}

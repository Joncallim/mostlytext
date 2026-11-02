import Darwin
import Foundation

public extension InstallationMigration {
    func pathsAcknowledged(_ prepared: PreparedInstallationMigration) throws -> Bool {
        let record = try require(prepared)
        guard let bytes = try storage.read("installation-paths.json") else { return false }
        try InstallationMigrationMarker.validate(bytes, record: record, phase: "paths")
        return true
    }

    func acknowledgePaths(_ prepared: PreparedInstallationMigration) throws {
        let record = try require(prepared)
        guard let complete = try storage.read("installation-complete.json")
        else { throw LegacyMigrationFailure.invalidPhase }
        try InstallationMigrationMarker.validate(complete, record: record, phase: "complete")
        try storage.publish(InstallationMigrationMarker(record: record, phase: "paths").encoded(),
                            as: "installation-paths.json")
    }

    func reviewAcknowledged(_ prepared: PreparedInstallationMigration) throws -> Bool {
        let record = try require(prepared)
        guard let bytes = try storage.read("installation-review.json") else { return false }
        try InstallationMigrationMarker.validate(bytes, record: record, phase: "review")
        return true
    }

    func acknowledgeReview(_ prepared: PreparedInstallationMigration) throws {
        let record = try require(prepared)
        guard try pathsAcknowledged(prepared) else { throw LegacyMigrationFailure.invalidPhase }
        try storage.publish(InstallationMigrationMarker(record: record, phase: "review").encoded(),
                            as: "installation-review.json")
    }

    /// Retry may abandon only a transaction that has not changed preferences
    /// and whose published working copy still matches its initial snapshot.
    /// Every retired object remains under the same private, locked root.
    @discardableResult
    func retireUnapplied(currentPreferences: InstallationPreferences) throws -> Bool {
        try storage.verify()
        guard try storage.read("installation-preferences.json") == nil,
              try storage.read("installation-complete.json") == nil,
              try storage.read("installation-paths.json") == nil,
              let bytes = try storage.read("installation-plan.json") else { return false }
        let record = try InstallationMigrationRecord.decode(bytes)
        guard record.sourcePaths == sources.map(\.path), record.destinationDomains == domains,
              try currentPreferences.digests == record.beforePreferenceDigests else { return false }
        var info = stat()
        if fstatat(storage.directory, Self.generation, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            try verifyGeneration(record)
            try renameRetained(Self.generation, to: "retired-installation-" + UUID().uuidString)
        } else if errno != ENOENT {
            throw LegacyMigrationFailure.changedStorage
        }
        try renameRetained("installation-plan.json", to: "retired-plan-" + UUID().uuidString + ".json")
        pending = nil
        return true
    }

    private func renameRetained(_ from: String, to destinationName: String) throws {
        try storage.verify()
        guard renameatx_np(storage.directory, from, storage.directory, destinationName, UInt32(RENAME_EXCL)) == 0,
              fsync(storage.directory) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        try storage.verify()
    }
}

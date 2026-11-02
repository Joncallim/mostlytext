import Foundation

extension InstallationMigration {
    func loadOrCreateRecord(sourcePreferences: InstallationPreferences,
                            currentPreferences: InstallationPreferences) throws -> InstallationMigrationRecord {
        let tree = InstallationTree(storage: storage)
        let existing = try storage.read("installation-plan.json")
        let record: InstallationMigrationRecord
        if let existing {
            record = try InstallationMigrationRecord.decode(existing)
            guard record.sourcePaths == sources.map(\.path), record.destinationDomains == domains else {
                throw LegacyMigrationFailure.unboundDestination
            }
        } else {
            guard try storage.read("installation-complete.json") == nil,
                  try storage.read("installation-preferences.json") == nil
            else { throw LegacyMigrationFailure.invalidRecord }
            let trees = try sources.map { try tree.snapshot($0) }
            let adopts = !currentPreferences.populated && trees[2].entries.isEmpty
            record = try InstallationMigrationRecord(
                version: 1, id: UUID(), sourcePaths: sources.map(\.path), destinationDomains: domains, trees: trees,
                sourcePreferenceDigests: sourcePreferences.digests, beforePreferenceDigests: currentPreferences.digests,
                adoptsDevelopment: adopts, completedOriginalImport: adopts && sourcePreferences.application != nil
                    && originalImportIsComplete(snapshot: trees[1])
            )
            try storage.publish(record.encoded(), as: "installation-plan.json")
            try checkpoint?(.afterPlan)
        }
        return record
    }
}

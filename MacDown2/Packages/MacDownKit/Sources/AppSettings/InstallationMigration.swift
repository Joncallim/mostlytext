import Darwin
import Foundation

/// Required development-installation preservation. Keep this actor alive for
/// the application's lifetime: its root lock excludes another ordinary writer.
public actor InstallationMigration {
    let storage: MigrationJournalDirectory
    let sources: [URL]
    let domains: [String]
    let owner = UUID()
    var pending: InstallationMigrationRecord?
    let checkpoint: (@Sendable (Checkpoint) throws -> Void)?
    static let generation = "installation-v1"

    public enum Checkpoint: Sendable { case afterPlan, afterCopy, afterPublish, afterPreferenceAcknowledgement,
                                            afterComplete
    }

    public init(developmentDirectory: URL, developmentImportJournal: URL, currentDirectory: URL,
                destinationDirectory: URL,
                applicationDomain: String = ApplicationStorageLocations.applicationDomain,
                workspaceDomain: String = ApplicationStorageLocations.workspaceDomain) throws {
        storage = try MigrationJournalDirectory(url: destinationDirectory)
        sources = [developmentDirectory, developmentImportJournal, currentDirectory]
        domains = [applicationDomain, workspaceDomain]; checkpoint = nil
        try Self.validateConfiguration(sources: sources, destination: destinationDirectory, domains: domains)
    }

    init(developmentDirectory: URL, developmentImportJournal: URL, currentDirectory: URL,
         destinationDirectory: URL, applicationDomain: String, workspaceDomain: String,
         checkpoint: @escaping @Sendable (Checkpoint) throws -> Void) throws {
        storage = try MigrationJournalDirectory(url: destinationDirectory)
        sources = [developmentDirectory, developmentImportJournal, currentDirectory]
        domains = [applicationDomain, workspaceDomain]; self.checkpoint = checkpoint
        try Self.validateConfiguration(sources: sources, destination: destinationDirectory, domains: domains)
    }

    public func close() {
        storage.close()
    }

    /// Historical completion/published recovery does not depend on a later
    /// launch of the development application or its changed preference domain.
    public func resumePublished() throws -> PreparedInstallationMigration? {
        try storage.verify()
        guard try storage.read("installation-plan.json") != nil, generationExists() else { return nil }
        let empty = try InstallationPreferences(application: nil as [String: Any]?, workspace: nil)
        return try prepare(sourcePreferences: empty, currentPreferences: empty)
    }

    public func prepare(sourcePreferences: InstallationPreferences,
                        currentPreferences: InstallationPreferences) throws -> PreparedInstallationMigration {
        try storage.verify()
        let tree = InstallationTree(storage: storage)
        let record = try loadOrCreateRecord(
            sourcePreferences: sourcePreferences,
            currentPreferences: currentPreferences
        )
        pending = record
        let ack = try storage.read("installation-preferences.json")
        let complete = try storage.read("installation-complete.json")
        if let ack {
            try InstallationMigrationMarker.validate(ack, record: record, phase: "preferences")
        }
        if let complete {
            guard ack != nil else { throw LegacyMigrationFailure.invalidRecord }
            try InstallationMigrationMarker.validate(complete, record: record, phase: "complete")
            return try prepared(record, stage: nil, acknowledged: true, complete: true)
        }
        // Reflush a plan that might have been renamed just before interruption.
        try storage.publish(record.encoded(), as: "installation-plan.json")
        if generationExists() {
            try verifyGeneration(record)
            return try prepared(record, stage: nil, acknowledged: ack != nil, complete: false)
        }
        guard ack == nil, try sourcePreferences.digests == record.sourcePreferenceDigests,
              try currentPreferences.digests == record.beforePreferenceDigests else {
            throw LegacyMigrationFailure.transactionExists
        }
        try verifySources(record)
        let stage = "installation-stage-" + UUID().uuidString
        guard mkdirat(storage.directory, stage, 0o700) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        let descriptor = try tree.openParent(storage.directory, components: [stage]); defer { Darwin.close(descriptor) }
        try populate(
            record,
            stage: descriptor,
            sourcePreferences: sourcePreferences,
            currentPreferences: currentPreferences
        )
        try checkpoint?(.afterCopy)
        try verifySources(record)
        try verifyStage(record, descriptor: descriptor)
        return try prepared(record, stage: stage, acknowledged: false, complete: false)
    }

    public func publishFiles(_ prepared: PreparedInstallationMigration) throws -> PreparedInstallationMigration {
        let record = try require(prepared)
        guard !prepared.isComplete else { return prepared }
        if let stage = prepared.stageName {
            try verifySources(record)
            let tree = InstallationTree(storage: storage)
            let descriptor = try tree
                .openParent(storage.directory, components: [stage]); defer { Darwin.close(descriptor) }
            try verifyStage(record, descriptor: descriptor)
            try storage.verify()
            guard renameatx_np(storage.directory, stage, storage.directory, Self.generation, UInt32(RENAME_EXCL)) == 0
            else { throw LegacyMigrationFailure.unavailable(errno) }
            try checkpoint?(.afterPublish)
        }
        guard fsync(storage.directory) == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        try verifyGeneration(record)
        return try self.prepared(record, stage: nil, acknowledged: prepared.preferencesAcknowledged, complete: false)
    }

    public func revalidateSources(_ prepared: PreparedInstallationMigration) throws {
        let record = try require(prepared)
        if !prepared.preferencesAcknowledged, !prepared.isComplete {
            try verifySources(record)
        }
    }

    public func acknowledgePreferences(_ prepared: PreparedInstallationMigration) throws {
        let record = try require(prepared)
        try verifyGeneration(record)
        try storage.publish(InstallationMigrationMarker(record: record, phase: "preferences").encoded(),
                            as: "installation-preferences.json")
        try checkpoint?(.afterPreferenceAcknowledgement)
    }

    public func complete(_ prepared: PreparedInstallationMigration) throws {
        let record = try require(prepared)
        guard let ack = try storage.read("installation-preferences.json")
        else { throw LegacyMigrationFailure.invalidPhase }
        try InstallationMigrationMarker.validate(ack, record: record, phase: "preferences")
        try verifyGeneration(record)
        try storage.publish(InstallationMigrationMarker(record: record, phase: "complete").encoded(),
                            as: "installation-complete.json")
        try checkpoint?(.afterComplete)
    }

    func require(_ prepared: PreparedInstallationMigration) throws -> InstallationMigrationRecord {
        try storage.verify()
        guard prepared.owner == owner, let pending, prepared.recordID == pending.id else {
            throw LegacyMigrationFailure.transactionExists
        }
        return pending
    }

    func verifySources(_ record: InstallationMigrationRecord) throws {
        let tree = InstallationTree(storage: storage)
        for (source, captured) in zip(sources, record.trees) {
            guard try tree.snapshot(source).encoded() == captured.encoded()
            else { throw LegacyMigrationFailure.changedStorage }
        }
    }

    private func generationExists() -> Bool {
        var raw = stat()
        return fstatat(storage.directory, Self.generation, &raw, AT_SYMLINK_NOFOLLOW) == 0
    }

    private static func validateConfiguration(sources: [URL], destination: URL, domains: [String]) throws {
        guard domains.allSatisfy(UserDefaultsAppSettingsStore.admitsPersistenceDomain), domains[0] != domains[1],
              sources
              .allSatisfy({ $0.isFileURL && ($0.host == nil || $0.host == "") && $0.user == nil && $0.password == nil
                      && $0.query == nil && $0.fragment == nil && !$0.path.utf8.contains(0)
                      && $0.pathComponents.allSatisfy { $0 != "." && $0 != ".." } }) else {
            throw LegacyMigrationFailure.unboundDestination
        }
        let root = destination.standardizedFileURL.path
        for source in sources.prefix(2) {
            let path = source.standardizedFileURL.path
            guard path != root, !path.hasPrefix(root + "/"), !root.hasPrefix(path + "/") else {
                throw LegacyMigrationFailure.unsafeStorage
            }
        }
    }
}

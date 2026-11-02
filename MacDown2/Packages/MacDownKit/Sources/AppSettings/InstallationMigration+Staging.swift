import Darwin
import Foundation

extension InstallationMigration {
    func populate(_ record: InstallationMigrationRecord, stage: Int32,
                  sourcePreferences: InstallationPreferences, currentPreferences: InstallationPreferences) throws {
        let tree = InstallationTree(storage: storage)
        for (index, role) in ["Source", "EditorImport", "Current"].enumerated() {
            let root = try tree.makeDirectory(stage, components: [role]); defer { Darwin.close(root) }
            try tree.copy(record.trees[index], from: sources[index], into: root)
        }
        let state = try tree.makeDirectory(stage, components: ["State"]); defer { Darwin.close(state) }
        let index = record.adoptsDevelopment ? 0 : 2
        try tree.copy(record.trees[index], from: sources[index], into: state, workingCommands: true)
        let preferences = try tree.makeDirectory(stage, components: ["Preferences"])
        defer { Darwin.close(preferences) }
        let snapshots = [
            sourcePreferences.application,
            sourcePreferences.workspace,
            currentPreferences.application,
            currentPreferences.workspace,
        ]
        for (name, bytes) in zip(Self.preferenceNames, snapshots) {
            if let bytes {
                try tree.write(bytes, beneath: preferences, components: [name])
            }
        }
        try tree.syncDirectories(stage)
    }

    func verifyStage(_ record: InstallationMigrationRecord, descriptor: Int32) throws {
        let tree = InstallationTree(storage: storage)
        for (index, role) in ["Source", "EditorImport", "Current"].enumerated() {
            let child = try tree.openParent(descriptor, components: [role]); defer { Darwin.close(child) }
            try storage.validate(child, kind: S_IFDIR, mode: 0o700)
            try tree.verifyCopy(record.trees[index], beneath: child)
        }
        let state = try tree.openParent(descriptor, components: ["State"]); defer { Darwin.close(state) }
        try storage.validate(state, kind: S_IFDIR, mode: 0o700)
        try tree.verifyCopy(record.trees[record.adoptsDevelopment ? 0 : 2], beneath: state, workingCommands: true)
        let source = try preferences(beneath: descriptor, source: true)
        let current = try preferences(beneath: descriptor, source: false)
        guard try source.digests == record.sourcePreferenceDigests,
              try current.digests == record.beforePreferenceDigests else { throw LegacyMigrationFailure.invalidRecord }
    }

    func verifyGeneration(_ record: InstallationMigrationRecord) throws {
        let tree = InstallationTree(storage: storage)
        let descriptor = try tree
            .openParent(storage.directory, components: [Self.generation]); defer { Darwin.close(descriptor) }
        try storage.validate(descriptor, kind: S_IFDIR, mode: 0o700)
        try verifyStage(record, descriptor: descriptor)
        try tree.syncDirectories(descriptor)
        try storage.verify()
    }

    func prepared(_ record: InstallationMigrationRecord, stage: String?, acknowledged: Bool,
                  complete: Bool) throws -> PreparedInstallationMigration {
        let tree = InstallationTree(storage: storage)
        let name = stage ?? Self.generation
        let descriptor = try tree.openParent(storage.directory, components: [name]); defer { Darwin.close(descriptor) }
        try storage.validate(descriptor, kind: S_IFDIR, mode: 0o700)
        let state = try tree.openParent(descriptor, components: ["State"]); defer { Darwin.close(state) }
        try storage.validate(state, kind: S_IFDIR, mode: 0o700)
        let desired = try preferences(beneath: descriptor, source: record.adoptsDevelopment)
        let expected = record.adoptsDevelopment ? record.sourcePreferenceDigests : record.beforePreferenceDigests
        guard try desired.digests == expected else { throw LegacyMigrationFailure.invalidRecord }
        let directory = storage.url.appendingPathComponent(name, isDirectory: true)
        return PreparedInstallationMigration(
            locations: ApplicationStorageLocations(
                dataDirectory: directory.appendingPathComponent("State", isDirectory: true),
                preservedDirectory: directory.appendingPathComponent("Source", isDirectory: true)
            ),
            desiredPreferences: desired, beforePreferenceDigests: record.beforePreferenceDigests,
            sourcePreferenceDigests: record.sourcePreferenceDigests, isComplete: complete,
            preferencesAcknowledged: acknowledged, adoptsDevelopment: record.adoptsDevelopment,
            completedOriginalImport: record.completedOriginalImport,
            hasPreservedDevelopmentState: !record.trees[0].entries.isEmpty || record.sourcePreferenceDigests
                .contains { $0 != "absent" },
            owner: owner, recordID: record.id, stageName: stage
        )
    }

    private static let preferenceNames = [
        "source-application.plist",
        "source-workspace.plist",
        "current-application.plist",
        "current-workspace.plist",
    ]

    private func preferences(beneath descriptor: Int32, source: Bool) throws -> InstallationPreferences {
        let tree = InstallationTree(storage: storage)
        let parent = try tree.openParent(descriptor, components: ["Preferences"]); defer { Darwin.close(parent) }
        let offset = source ? 0 : 2
        return try InstallationPreferences(
            application: tree.readFile(beneath: parent, components: [Self.preferenceNames[offset]]),
            workspace: tree.readFile(beneath: parent, components: [Self.preferenceNames[offset + 1]])
        )
    }

    func originalImportIsComplete(snapshot: InstallationTreeSnapshot) throws -> Bool {
        guard snapshot.root != nil else { return false }
        let descriptor = open(sources[1].path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard descriptor >= 0 else { throw LegacyMigrationFailure.changedStorage }
        defer { Darwin.close(descriptor) }
        let tree = InstallationTree(storage: storage)
        guard let planBytes = try tree.readFile(beneath: descriptor, components: ["plan.json"]) else { return false }
        let plan = try LegacyEditorJournalPlan.decode(planBytes)
        guard plan.domain == ApplicationStorageLocations.developmentDomain
        else { throw LegacyMigrationFailure.unboundDestination }
        let acknowledged = try tree.readFile(beneath: descriptor, components: ["acknowledged.json"])
        let complete = try tree.readFile(beneath: descriptor, components: ["complete.json"])
        if let acknowledged {
            try validateOriginalMarker(acknowledged, plan: planBytes, phase: "acknowledged")
        }
        if let complete {
            guard acknowledged != nil else { throw LegacyMigrationFailure.invalidPhase }
            try validateOriginalMarker(complete, plan: planBytes, phase: "complete")
            return true
        }
        return false
    }

    private struct OriginalMarker: Codable {
        let version: Int
        let planDigest: String
        let phase: String
    }

    private func validateOriginalMarker(_ bytes: Data, plan: Data, phase: String) throws {
        try LegacyEditorJournalPlan.validateJSON(bytes)
        let marker = try JSONDecoder().decode(OriginalMarker.self, from: bytes)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard marker.version == 1, marker.planDigest == LegacyEditorJournalPlan.digest(plan), marker.phase == phase,
              try encoder.encode(marker) == bytes else { throw LegacyMigrationFailure.invalidRecord }
    }
}

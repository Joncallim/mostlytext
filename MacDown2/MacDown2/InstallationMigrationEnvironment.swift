import AppKit
import AppSettings
import FileTree
import Foundation

@MainActor
enum InstallationMigrationEnvironment {
    static func sourcePreferences() throws -> InstallationPreferences {
        guard NSRunningApplication
            .runningApplications(withBundleIdentifier: ApplicationStorageLocations.developmentDomain)
            .isEmpty else { throw LegacyMigrationFailure.busy }
        return try InstallationPreferences(
            application: UserDefaults.standard.persistentDomain(forName: ApplicationStorageLocations.developmentDomain),
            workspace: UserDefaults.standard
                .persistentDomain(forName: ApplicationStorageLocations.developmentWorkspaceDomain)
        )
    }

    static func makeStartup(store: UserDefaultsAppSettingsStore, identity: String,
                            disabled: Bool) -> ApplicationMigrationStartup {
        guard let publisher = try? InstallationPreferencesPublisher() else {
            preconditionFailure("The compiled installation domains must be valid")
        }
        return ApplicationMigrationStartup(disabled: disabled, publisher: publisher, makeInstallation: {
            guard identity == ApplicationStorageLocations.applicationDomain else {
                throw LegacyMigrationFailure.unboundDestination
            }
            return try await Task.detached {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: true)
                guard support.standardizedFileURL == support.resolvingSymlinksInPath().standardizedFileURL else {
                    throw LegacyMigrationFailure.unsafeStorage
                }
                return try InstallationMigration(
                    developmentDirectory: support.appendingPathComponent("MacDown 2", isDirectory: true),
                    developmentImportJournal: support.appendingPathComponent(
                        ApplicationStorageLocations.developmentDomain + "-editor-import-v1", isDirectory: true
                    ),
                    currentDirectory: support.appendingPathComponent("MostlyText/State", isDirectory: true),
                    destinationDirectory: support.appendingPathComponent("MostlyText", isDirectory: true)
                )
            }.value
        }, source: { try sourcePreferences() }, validate: { locations, preferences in
            try InstallationContentAdmission.validate(locations, preferences: preferences)
        }, relocate: { locations in
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false)
            let old = support.appendingPathComponent("MacDown 2", isDirectory: true)
            try await InstallationManagedPaths.relocate(from: old, to: locations)
            try relocateRecentBookmarks(from: old, to: locations, publisher: publisher)
        }, makeOptional: { completed in
            LegacyImportEnvironment.makeStartup(
                store: store,
                identity: identity,
                disabled: disabled,
                skipNewOffer: completed
            )
        })
    }

    private static func relocateRecentBookmarks(from source: URL, to locations: ApplicationStorageLocations,
                                                publisher: InstallationPreferencesPublisher) throws {
        let snapshot = try publisher.snapshot()
        guard var domain = try InstallationPreferences.decode(snapshot.application) else { return }
        let map: (URL) throws -> URL? = { url in
            guard let new = InstallationManagedPaths.mapped(url, from: source, to: locations.dataDirectory)
            else { return nil }
            try InstallationManagedPaths.validateOwned(new, beneath: locations.dataDirectory)
            return new
        }
        if let records = domain["fileTree.recentRoots"] as? [Data] {
            domain["fileTree.recentRoots"] = try RecentFolderRoots.relocatedInstallationBookmarks(records, map: map)
        }
        if let records = domain["fileTree.recentFiles"] as? [Data] {
            domain["fileTree.recentFiles"] = try RecentFileDocuments.relocatedInstallationBookmarks(records, map: map)
        }
        let desired = try InstallationPreferences(application: domain,
                                                  workspace: InstallationPreferences.decode(snapshot.workspace))
        try publisher.publish(desired: desired, before: snapshot.digests, revalidateSource: {})
    }
}

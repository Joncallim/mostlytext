import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Themes
import Workspace

@MainActor
enum InstallationContentAdmission {
    static func validate(_ locations: ApplicationStorageLocations, preferences: InstallationPreferences) throws {
        let application = try InstallationPreferences.decode(preferences.application) ?? [:]
        let workspace = try InstallationPreferences.decode(preferences.workspace) ?? [:]
        guard try UserDefaultsAppSettingsStore.admitsInstallationPreferences(preferences.application),
              UserDefaultsThemePreferenceStore.admitsInstallationPreferences(application),
              FileTreeInstallationAdmission.admits(application),
              WorkspaceStateStore.admitsInstallationPreferences(workspace),
              WorkspaceSessionStore(fileURL: locations.session).inspectSession().permitsPublication else {
            throw LegacyMigrationFailure.invalidRecord
        }
        let fence = locations.recovery.appendingPathComponent("recovery-fences.json")
        if FileManager.default.fileExists(atPath: fence.path) {
            guard try RecoveryBuffer.admitsInstallationLedger(Data(contentsOf: fence)) else {
                throw LegacyMigrationFailure.invalidRecord
            }
        }
        switch SnippetStore(fileURL: locations.snippets).load() {
        case .missing: break
        case let .loaded(library):
            guard library.skippedCount == 0 else { throw LegacyMigrationFailure.invalidRecord }
        case .unreadable, .unsupportedVersion: throw LegacyMigrationFailure.invalidRecord
        }
        if FileManager.default.fileExists(atPath: locations.themes.path) {
            for url in try FileManager.default.contentsOfDirectory(at: locations.themes,
                                                                   includingPropertiesForKeys: [.isRegularFileKey])
                where url.pathExtension == "json" {
                let bytes = try Data(contentsOf: url)
                _ = try ThemeFile.decode(bytes)
            }
        }
    }
}

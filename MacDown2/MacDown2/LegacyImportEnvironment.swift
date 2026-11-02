import AppKit
import AppSettings

/// Platform observations for the bounded, otherwise data-only importer.
@MainActor
enum LegacyImportEnvironment {
    static func resolveFont(_ request: LegacyPreferenceReport.FontRequest) -> LegacyResolvedFont? {
        guard let installed = NSFont(name: request.postScriptName, size: request.size),
              let family = installed.familyName,
              let ordinary = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: request.size)
        else { return nil }
        return LegacyResolvedFont(request: request, installedName: installed.fontName,
                                  installedFamily: family, installedSize: installed.pointSize,
                                  familyResolvedName: ordinary.fontName, familyResolvedSize: ordinary.pointSize)
    }

    static func currentSource() throws -> LegacyPreferenceSnapshot {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: LegacyPreferencesDetector.legacySuiteName
        ).isEmpty else { throw LegacyMigrationFailure.busy }
        return try LegacyPreferenceSnapshot(domain: UserDefaults.standard.persistentDomain(
            forName: LegacyPreferencesDetector.legacySuiteName
        ) ?? [:])
    }

    static func makeStartup(store: UserDefaultsAppSettingsStore, identity: String,
                            disabled: Bool, skipNewOffer: Bool = false) -> LegacyImportStartup {
        LegacyImportStartup(store: store, disabled: disabled, skipNewOffer: skipNewOffer, makeJournal: {
            try await Task.detached {
                let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                          in: .userDomainMask, appropriateFor: nil, create: true)
                guard support.standardizedFileURL == support.resolvingSymlinksInPath().standardizedFileURL else {
                    throw LegacyMigrationFailure.unsafeStorage
                }
                return try LegacyEditorMigrationJournal(directoryURL: support.appendingPathComponent(
                    identity + "-editor-import-v1", isDirectory: true
                ))
            }.value
        }, source: { try currentSource() }, resolveFont: { resolveFont($0) })
    }
}

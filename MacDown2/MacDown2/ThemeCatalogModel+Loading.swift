import Darwin
import Foundation
import Themes

extension ThemeCatalogModel {
    nonisolated static func openStore(location: Location) throws -> ThemeCatalogStore {
        if case let .existingDirectory(url) = location {
            return try ThemeCatalogStore(directoryURL: url)
        }
        let parent: URL
        let components: [String]
        switch location {
        case .applicationSupport:
            parent = FileManager.default.homeDirectoryForCurrentUser
            components = ["Library", "Application Support", "MacDown 2", "Themes"]
        case let .isolatedSession(url):
            parent = url
            components = ["themes"]
        case .existingDirectory:
            throw ThemeStorageError.invalidDirectory
        }
        guard let physical = realpath(parent.path, nil) else { throw ThemeStorageError.invalidDirectory }
        let url = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
        free(physical)
        return try ThemeCatalogStore.prepareManagedDirectory(beneath: url, components: components)
    }

    static func message(for error: Error) -> String {
        switch error {
        case ThemeFileError.fileTooLarge:
            String(localized: "Theme files are limited to 64 KiB.")
        case ThemeFileError.unsupportedVersion:
            String(localized: "This theme uses a newer file format. Its original file was preserved.")
        case is ThemeFileError:
            String(localized: "The theme file is invalid or uses unsupported settings.")
        case ThemeCatalogError.catalogFull:
            String(localized: "The Themes folder has reached its limit of 256 custom themes.")
        case ThemeCatalogError.staleImportPlan, ThemeStorageError.staleFile:
            String(localized: "The theme changed during this operation. Import it again to review the current version.")
        case let ThemeStorageError.recoveryRequired(name):
            String(
                localized: """
                A competing version was preserved in the Themes folder as \(name). \
                Review it before continuing.
                """
            )
        case ThemeStorageError.directoryChanged:
            String(localized: "The Themes folder moved or changed. Restart the app to open the current folder.")
        default:
            String(localized: "Custom themes are unavailable. Check access to the Themes folder.")
        }
    }
}

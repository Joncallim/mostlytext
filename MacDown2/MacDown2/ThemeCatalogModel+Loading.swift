import Darwin
import FileCore
import Foundation
import LocalResourceAccess
import Themes

/// Keep the failure category until the presenting view chooses its language.
/// Theme storage and file bytes are independent of the language used for UI copy.
enum ThemeCatalogProblem: Equatable {
    case fileTooLarge
    case unsupportedVersion
    case invalidTheme
    case catalogFull
    case stalePlan
    case recoveryRequired(name: String)
    case directoryChanged
    case operationNeedsAttention
    case unavailable

    init(error: Error) {
        switch error {
        case ThemeFileError.fileTooLarge, ResourceReadError.oversized: self = .fileTooLarge
        case ThemeFileError.unsupportedVersion: self = .unsupportedVersion
        case is ThemeFileError: self = .invalidTheme
        case ThemeCatalogError.catalogFull: self = .catalogFull
        case ThemeCatalogError.staleImportPlan, ThemeStorageError.staleFile: self = .stalePlan
        case let ThemeStorageError.recoveryRequired(name): self = .recoveryRequired(name: name)
        case ThemeStorageError.directoryChanged: self = .directoryChanged
        default: self = .unavailable
        }
    }

    func message(locale: Locale, bundle: Bundle = .main) -> String {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        switch self {
        case .fileTooLarge:
            return String(localized: "Theme files are limited to 64 KiB.", bundle: bundle, locale: locale)
        case .unsupportedVersion:
            return String(localized: "This theme uses a newer file format. Its original file was preserved.",
                          bundle: bundle, locale: locale)
        case .invalidTheme:
            return String(localized: "The theme file is invalid or uses unsupported settings.",
                          bundle: bundle, locale: locale)
        case .catalogFull:
            return String(localized: "The Themes folder has reached its limit of 256 custom themes.",
                          bundle: bundle, locale: locale)
        case .stalePlan:
            return String(
                localized: "The theme changed during this operation. Import it again to review the current version.",
                bundle: bundle,
                locale: locale
            )
        case let .recoveryRequired(name):
            return String(
                localized: """
                A competing version was preserved in the Themes folder as \(name). \
                Review it before continuing.
                """,
                bundle: bundle,
                locale: locale
            )
        case .directoryChanged:
            return String(localized: "The Themes folder moved or changed. Restart the app to open the current folder.",
                          bundle: bundle, locale: locale)
        case .operationNeedsAttention:
            return String(
                localized: "The theme operation completed, but storage needs attention. Review the Themes folder.",
                bundle: bundle,
                locale: locale
            )
        case .unavailable:
            return String(localized: "Custom themes are unavailable. Check access to the Themes folder.",
                          bundle: bundle, locale: locale)
        }
    }
}

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
        case let .managedInstallation(url):
            parent = url
            components = ["Themes"]
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
}

import Foundation

/// Keeps each folder-search count beside its noun so catalog plural rules
/// resolve before SwiftUI presents the message or accessibility label.
enum FolderSearchCountCopy {
    case confirmation(matches: Int, files: Int)
    case summary(matches: Int, files: Int)
    case unsearched(files: Int)
    case skipped(files: Int)
    case result(path: String, matches: Int)

    func message(bundle: Bundle = .main, locale: Locale = .current) -> String {
        switch self {
        case let .confirmation(matches, files):
            return String(localized: "Replace \(matches) matches in \(files) files?", bundle: bundle, locale: locale)
        case let .summary(matches, files):
            return String(localized: "Replaced \(matches) matches in \(files) files.", bundle: bundle, locale: locale)
        case let .unsearched(files):
            return String(localized: "\(files) files could not be searched and will not be changed.",
                          bundle: bundle, locale: locale)
        case let .skipped(files):
            return String(localized: "and \(files) more files not modified", bundle: bundle, locale: locale)
        case let .result(path, matches):
            let count = String(localized: "\(matches) matches", bundle: bundle, locale: locale)
            return String(localized: "Matches in \(path): \(count)", bundle: bundle, locale: locale)
        }
    }
}

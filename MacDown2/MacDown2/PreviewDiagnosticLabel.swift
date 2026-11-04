import Foundation

/// Whole catalog messages keep accessibility counts and nouns in the same
/// language. Authored diagnostic content is presented separately, verbatim.
enum PreviewDiagnosticLabel {
    case error(count: Int)
    case warning(count: Int)

    func message(bundle: Bundle = .main, locale: Locale = .current) -> String {
        switch self {
        case let .error(count):
            String(localized: "\(count) preview errors", bundle: bundle, locale: locale)
        case let .warning(count):
            String(localized: "\(count) preview warnings", bundle: bundle, locale: locale)
        }
    }
}

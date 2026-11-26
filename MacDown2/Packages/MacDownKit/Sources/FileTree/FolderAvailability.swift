import FileCore
import Foundation

public enum FolderAvailability: Sendable, Equatable {
    case noRoot
    case loading
    case rootUnreadable(reason: String)
    case rootVanished
    case empty
    case emptyAfterFilter
    case ready

    /// Keep the known watcher outcome as a category until the sidebar draws
    /// it. An OS-provided read error remains verbatim in `rootUnreadable`.
    public func message(locale: Locale) -> String? {
        switch self {
        case let .rootUnreadable(reason): reason
        case .rootVanished:
            String(
                localized: "The folder is no longer available.",
                bundle: ViewLocalizationBundle.resolve(locale: locale, in: .module),
                locale: locale
            )
        case .noRoot, .loading, .empty, .emptyAfterFilter, .ready: nil
        }
    }
}

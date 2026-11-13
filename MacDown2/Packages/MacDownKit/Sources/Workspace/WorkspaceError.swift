import FileCore
import Foundation

/// Errors surfaced by the workspace shell when routing commands to `FileCore`.
public enum WorkspaceError: Error {
    case openFailed(underlying: FileStoreError)
    case saveFailed(underlying: FileStoreError)
    /// A competing external writer was preserved separately after a failed
    /// conditional publication. The current document remains dirty.
    case conditionalPublicationRecoveryRequired(URL)
    /// The document was saved, but its prior crash-recovery record could not
    /// be safely migrated or removed. Keep the window open and retry cleanup,
    /// or use Save As after revealing the retained recovery copy.
    case recoveryCleanupRequired(URL)
    case noActiveDocument
    case unresolvedExternalConflict
    case backingFileUnavailable(FileBackingIssue)
    /// The text contains characters the target encoding cannot hold. Nothing
    /// was written and the document's encoding is unchanged.
    case textNotRepresentable(encodingName: String)
    /// Save As chose a file that is open in another window. Nothing was written.
    case destinationOpenInAnotherWindow(name: String)
}

extension WorkspaceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .openFailed:
            String(localized: "The document could not be opened.", bundle: .module)
        case .saveFailed:
            String(localized: "The document could not be saved.", bundle: .module)
        case let .conditionalPublicationRecoveryRequired(url):
            String(
                localized: """
                MostlyText preserved a competing version as \(url.lastPathComponent). \
                Reveal it, then use Save As to keep this copy.
                """,
                bundle: .module
            )
        case let .recoveryCleanupRequired(url):
            String(
                localized: """
                MostlyText retained recovery for \(url.lastPathComponent). Keep this window open and retry, \
                or use Save As after revealing the recovery copy.
                """,
                bundle: .module
            )
        case .noActiveDocument:
            String(localized: "There is no active document.", bundle: .module)
        case .unresolvedExternalConflict:
            String(
                localized: "Resolve the external file change before saving, or use Save As to keep this copy.",
                bundle: .module
            )
        case let .textNotRepresentable(encodingName):
            String(
                localized: """
                This text cannot be saved as \(encodingName) without losing characters. \
                Nothing was changed; choose another encoding, or delete an invisible byte-order-mark character \
                (U+FEFF or U+FFFE) at the very start of the text.
                """,
                bundle: .module
            )
        case let .destinationOpenInAnotherWindow(name):
            String(
                localized: "\(name) is open in another window. Close it there, or choose a different name.",
                bundle: .module
            )
        case let .backingFileUnavailable(issue):
            switch issue {
            case .missingOrMoved, .parentUnavailable:
                String(
                    localized: "The backing file is no longer available. Use Save As to keep this copy.",
                    bundle: .module
                )
            case .permissionDenied:
                String(
                    localized: "MostlyText cannot access the backing file. Use Save As to keep this copy.",
                    bundle: .module
                )
            case .notRegularFile:
                String(
                    localized: "The backing path is no longer a regular file. Use Save As to keep this copy.",
                    bundle: .module
                )
            case .ambiguousMove, .moveCollidesWithOpenDocument:
                String(
                    localized: "MostlyText could not safely follow the moved file. Use Save As to keep this copy.",
                    bundle: .module
                )
            case .readFailed:
                String(
                    localized: "The backing file cannot be read safely. Use Save As to keep this copy.",
                    bundle: .module
                )
            }
        }
    }
}

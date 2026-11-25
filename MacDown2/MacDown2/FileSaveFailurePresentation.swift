import FileCore
import Foundation

/// A human-readable description of a failed save. Mirrors
/// `FileOpenFailurePresentation` (`WindowCoordinator+OpenFailure.swift`):
/// `FileStoreError` carries no `LocalizedError` conformance of its own, and
/// the two operations fail for different reasons worded differently ("could
/// not be read" is wrong for a write that failed), so this is a distinct,
/// write-flavoured mapping rather than a shared one (#57).
enum FileSaveFailurePresentation {
    static func message(for error: FileStoreError, locale: Locale, bundle: Bundle = .main) -> String {
        switch error {
        case .writeFailed: String(localized: "The file could not be written.", bundle: bundle, locale: locale)
        case .permissionDenied:
            String(localized: "MostlyText does not have permission to write this file.", bundle: bundle, locale: locale)
        case .notRegularFile: String(localized: "This is not a regular file.", bundle: bundle, locale: locale)
        case .invalidURL: String(localized: "This is not a valid save location.", bundle: bundle, locale: locale)
        case .fileChangedDuringRead:
            String(localized: "The file changed on disk while saving. Try again.", bundle: bundle, locale: locale)
        // Thrown both when the containing folder is gone and when the file
        // itself was deleted/moved/trashed while its folder is untouched —
        // exactly issue #57's headline scenario — so this must not name
        // "folder" specifically (adversarial review finding).
        case .fileMissing:
            String(localized: "The file could not be found. It may have been moved, renamed, or deleted.",
                   bundle: bundle, locale: locale)
        // `.textNotRepresentable` is intercepted by the model into
        // `WorkspaceError.textNotRepresentable` (which names the attempted
        // encoding); it shares this wording only for switch exhaustiveness.
        case .encodingDetectionFailed, .textNotRepresentable:
            String(localized: "The text could not be written in the file's text encoding.",
                   bundle: bundle, locale: locale)
        case let .decodingFailed(diagnostics):
            diagnostics.first?.message ?? String(localized: "The file's contents could not be verified after saving.",
                                                 bundle: bundle, locale: locale)
        case .conditionalPublicationRecoveryRequired:
            // Unreachable in practice: `workspaceError(for:)`
            // (`WorkspaceModel+SavingSupport.swift`) intercepts this case
            // before it ever becomes `.saveFailed(underlying:)`, mapping it
            // instead to the distinct `WorkspaceError
            // .conditionalPublicationRecoveryRequired(url)` that
            // `WorkspaceRecoveryRequiredNotice` renders with the actual
            // filename. Kept here only for switch exhaustiveness.
            String(localized: "A competing version was preserved separately.", bundle: bundle, locale: locale)
        case .readFailed:
            String(localized: "The file could not be verified after saving.", bundle: bundle, locale: locale)
        }
    }
}

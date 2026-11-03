import Foundation

/// Errors surfaced by export composition and writing.
///
/// `LocalizedError` is deliberate: the app presents failures with
/// `error.localizedDescription`, which for a bare Swift error is an opaque
/// "operation couldn't be completed" string. Conforming here is what makes the
/// prose below reach the user.
public enum ExportError: Error, LocalizedError, CustomStringConvertible {
    /// A self-contained HTML or PDF export encountered a resource that cannot
    /// be embedded (missing local file, or a remote reference that is never
    /// fetched during offline export).
    case unresolvedResources([ExportDiagnostic])
    /// A self-contained export encountered authored raw HTML. Arbitrary
    /// resource-bearing attributes cannot be proven closed, so the document
    /// must not claim to be self-contained.
    case rawHTMLNotEmbeddable
    /// The `ParseExecuting` parse failed.
    case parseFailed(underlying: Error)
    /// The cmark render failed.
    case renderFailed(underlying: Error)
    /// The output could not be written to disk.
    case writeFailed(underlying: Error)
    /// The target directory does not exist and could not be created.
    case invalidDestination(String)
    /// The document, or what it composes to, is past an export safety gate.
    case budgetExceeded(String)
    /// The optional generated SVG path could not prove its final output safe.
    case validatedPublicationRejected
    /// Generated image substitution authority is absent, stale or malformed.
    case invalidResourceSlots
    case invalidSourceSnapshot
    /// Destination/sidecar identity or ownership could not be retained.
    case unsafePublication
    case destinationChanged
    case destinationIsOpenDocument
    case publicationRecoveryRequired(URL)
    case recoveryStorageUnavailable(URL)

    public var description: String {
        switch self {
        case let .unresolvedResources(diagnostics):
            let listed = Self.summarise(diagnostics)
            return String(
                localized: "This export must embed every image, but some could not be resolved:\n\(listed)"
            )
        case .rawHTMLNotEmbeddable:
            return String(
                localized: """
                This document contains raw HTML, which cannot be embedded in a self-contained file. \
                Export it as HTML instead.
                """
            )
        case let .parseFailed(error):
            return String(localized: "Markdown parse failed: \(error.localizedDescription)", bundle: .module)
        case let .renderFailed(error):
            return String(localized: "HTML rendering failed: \(error.localizedDescription)", bundle: .module)
        case let .writeFailed(error):
            return String(localized: "Writing export output failed: \(error.localizedDescription)", bundle: .module)
        case let .invalidDestination(path):
            return String(localized: "Export destination is invalid: \(path)", bundle: .module)
        case let .budgetExceeded(detail):
            return String(localized: "This document is too large to export: \(detail).", bundle: .module)
        case let .recoveryStorageUnavailable(url):
            return String(localized: "Export recovery storage is unavailable or in use: \(url.path)", bundle: .module)
        case let .publicationRecoveryRequired(url):
            return String(localized: "An export staging file needs recovery at: \(url.path)", bundle: .module)
        case .unsafePublication:
            return String(localized: "The export destination or assets could not be safely reused.", bundle: .module)
        case .destinationChanged:
            return String(
                localized: "The export destination changed after it was selected. Choose it again.",
                bundle: .module
            )
        case .destinationIsOpenDocument:
            return String(
                localized: "Choose an export destination that is not a source or open document.",
                bundle: .module
            )
        case .invalidResourceSlots:
            return String(localized: "The export image references could not be safely assembled.", bundle: .module)
        case .invalidSourceSnapshot:
            return String(
                localized: "The export inputs no longer match their prepared source. Try exporting again.",
                bundle: .module
            )
        case .validatedPublicationRejected:
            return String(
                localized: "The generated diagram could not be safely included in this export.",
                bundle: .module
            )
        }
    }

    public var errorDescription: String? {
        description
    }

    /// How many unresolved resources one message lists before it counts the
    /// rest. A document with two hundred broken images is still one alert.
    private static let listedAtMost = 5

    private static func summarise(_ diagnostics: [ExportDiagnostic]) -> String {
        let listed = diagnostics.prefix(listedAtMost).map(\.message).joined(separator: "\n")
        guard diagnostics.count > listedAtMost else { return listed }
        let remaining = diagnostics.count - listedAtMost
        return listed + "\n" + String(localized: "…and \(remaining) more.", bundle: .module)
    }

    /// The actionable next step, shown under the message in the app's alert.
    public var recoverySuggestion: String? {
        switch self {
        case .unresolvedResources:
            String(
                localized: "Fix the image paths, or export as HTML, which keeps unresolved references as authored."
            )
        case .rawHTMLNotEmbeddable:
            String(localized: "Choose the HTML format, which preserves authored raw HTML.", bundle: .module)
        case .parseFailed, .renderFailed:
            nil
        case .writeFailed:
            String(localized: "Check that the destination folder exists and is writable.", bundle: .module)
        case .invalidDestination:
            String(localized: "Choose a different destination folder.", bundle: .module)
        case .budgetExceeded:
            String(localized: "Split the document, or reduce the size of the images it references.", bundle: .module)
        case .recoveryStorageUnavailable:
            String(
                localized: """
                Finish other exports and try again. If this continues, \
                preserve the recovery folder and contact support.
                """,
                bundle: .module
            )
        case .publicationRecoveryRequired:
            String(localized: "Preserve that file and choose another export destination.", bundle: .module)
        case .unsafePublication, .destinationChanged, .destinationIsOpenDocument:
            String(
                localized: "Choose another export name or destination. Existing files have been preserved.",
                bundle: .module
            )
        case .invalidResourceSlots, .invalidSourceSnapshot:
            String(localized: "Try exporting again from the original document.", bundle: .module)
        case .validatedPublicationRejected:
            String(localized: "Try exporting the diagram as its authored source.", bundle: .module)
        }
    }
}

import Foundation

/// Assembles admitted HTML before entering the shared descriptor-relative
/// publication boundary. Existing unknown/legacy sidecars are preserved.
enum ExportFileWriter {
    static let markerFileName = ".macdown-export-marker"
    /// Legacy bytes are retained for compatibility fixtures; never adopted as v2 ownership.
    static let markerContent = "macdown-export-v1\n"

    /// Writes an HTML export. `target` must be an `.html` target; PDF is written
    /// by the app's WebKit adapter.
    static func writeHTML(_ prepared: PreparedExportDocument, to target: ExportTarget,
                          limit: Int = ExportResourceBudget.maxFinalHTMLUTF8Bytes,
                          lease: ExportLifetimeLease = ExportLifetimeLease(),
                          hooks: ExportPublicationHooks = .init()) throws -> ExportResult {
        guard case let .html(url, mode) = target else {
            throw ExportError.invalidDestination("PDF targets are written by the PDF adapter, not the HTML writer")
        }

        let html: String = switch mode {
        case .selfContained:
            try ExportHTMLWriter.selfContainedHTML(from: prepared, limit: limit)
        case let .standalone(style):
            try ExportHTMLWriter.companionHTML(from: prepared, style: style, limit: limit)
        }

        var resources: [ExportResource] = []
        if case let .standalone(style) = mode {
            resources = prepared.manifest.resources
            if style ==
                .linked {
                resources.append(ExportHTMLWriter.linkedStylesheetResource(for: prepared.stylesheet))
            }
        }
        let input = HTMLFilePublicationInput(
            url: url, mode: mode, bytes: Data(html.utf8), resources: resources,
            assetsDirectoryName: prepared.assetsDirectoryName, diagnostics: prepared.diagnostics
        )
        return try ExportFilePublication.write(input, lease: lease, hooks: hooks)
    }

    /// The opt-in path consumes the inspected UTF-8 bytes directly. Existing
    /// content-addressed assets are verified and left untouched, so a failed
    /// replacement cannot damage resources used by the previous primary.
    static func writeValidatedHTML(
        _ validated: ValidatedExportHTML, lease: ExportLifetimeLease,
        afterCompanionDirectoryOpened: (() -> Void)? = nil,
        beforePromotion: (() -> Void)? = nil
    ) throws -> ExportResult {
        try ValidatedFilePublication.write(
            validated, lease: lease,
            afterCompanionDirectoryOpened: afterCompanionDirectoryOpened,
            beforePromotion: beforePromotion
        )
    }
}

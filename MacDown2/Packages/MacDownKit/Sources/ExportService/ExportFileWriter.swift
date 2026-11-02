import Foundation

/// Writes export output to disk with explicit ownership and primary-last
/// durability (issue #49).
///
/// Ownership contract:
/// - The companion directory is exactly `prepared.assetsDirectoryName` — the
///   primary file's own basename — next to the primary file; callers cannot
///   redirect it, and two documents exported into the same folder never share
///   one, so exporting one document can never overwrite or expose another's
///   companions.
/// - A versioned marker (`<name>.assets/.macdown-export-marker`) is written
///   before any resource is written, establishing the reserved namespace.
/// - Only the reserved namespace is mutated: the marker, `.tmp` scratch files,
///   and content-addressed `<64hex>.<ext>` resources (images and, for linked
///   CSS, the stylesheet itself). Non-reserved user files are never deleted or
///   overwritten.
///
/// Durability contract:
/// - Required resources are written before the primary HTML is atomically
///   promoted, so the HTML never appears before its assets do.
/// - There is no claim of multi-file atomicity; each file is written atomically
///   on its own.
enum ExportFileWriter {
    static let markerFileName = ".macdown-export-marker"
    static let markerContent = "macdown-export-v1\n"

    /// Writes an HTML export. `target` must be an `.html` target; PDF is written
    /// by the app's WebKit adapter.
    static func writeHTML(_ prepared: PreparedExportDocument, to target: ExportTarget,
                          limit: Int = ExportResourceBudget.maxFinalHTMLUTF8Bytes) throws -> ExportResult {
        guard case let .html(url, mode) = target else {
            throw ExportError.invalidDestination("PDF targets are written by the PDF adapter, not the HTML writer")
        }

        let directory = url.deletingLastPathComponent()

        var companionFiles: [URL] = []
        let html: String = switch mode {
        case .selfContained:
            try ExportHTMLWriter.selfContainedHTML(from: prepared, limit: limit)
        case let .standalone(style):
            try ExportHTMLWriter.companionHTML(from: prepared, style: style, limit: limit)
        }

        // Complete admission before creating a destination or touching sidecars.
        try Task.checkCancellation()
        try ensureDirectory(directory)
        if case let .standalone(style) = mode {
            companionFiles = try writeCompanions(prepared, style: style, nextTo: url)
        }

        // Primary-last: promote the HTML only after its resources exist.
        try writeAtomically(Data(html.utf8), to: url)

        return ExportResult(primaryFile: url, companionFiles: companionFiles, diagnostics: prepared.diagnostics)
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

    /// Writes every companion file a `.standalone` export needs: the resource
    /// manifest (marker first) when there are images, and the linked
    /// stylesheet when `style` calls for one. Both share one assets directory,
    /// created at most once.
    ///
    /// A document with neither — no images and embedded CSS — gets no
    /// companion directory at all: an empty folder beside every export would
    /// be litter, not output.
    private static func writeCompanions(
        _ prepared: PreparedExportDocument,
        style: ExportStyleEmbedding,
        nextTo url: URL
    ) throws -> [URL] {
        let needsAssetsDirectory = !prepared.manifest.resources.isEmpty || style == .linked
        guard needsAssetsDirectory else { return [] }

        let assetsDir = try ensureAssetsDirectory(prepared.assetsDirectoryName, nextTo: url)
        var written = [assetsDir.appendingPathComponent(markerFileName)]

        for resource in prepared.manifest.resources {
            let fileURL = assetsDir.appendingPathComponent(resource.identity.fileName)
            try writeAtomically(resource.bytes, to: fileURL)
            written.append(fileURL)
        }

        if case .linked = style {
            // The same computation `companionHTML` used for the `<link>` href,
            // so the file this writes always exists at the reference the body
            // actually points to.
            let resource = ExportHTMLWriter.linkedStylesheetResource(for: prepared.stylesheet)
            let cssURL = assetsDir.appendingPathComponent(resource.identity.fileName)
            try writeAtomically(resource.bytes, to: cssURL)
            written.append(cssURL)
        }

        return written
    }

    /// Creates `<name>` next to the primary file (if needed) and ensures its
    /// ownership marker is in place, before any resource is written into it.
    private static func ensureAssetsDirectory(_ name: String, nextTo url: URL) throws -> URL {
        let assetsDir = url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        try ensureDirectory(assetsDir)
        try ensureMarker(at: assetsDir.appendingPathComponent(markerFileName))
        return assetsDir
    }

    private static func ensureMarker(at url: URL) throws {
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == markerContent {
            return
        }
        try writeAtomically(Data(markerContent.utf8), to: url)
    }

    private static func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ExportError.invalidDestination(url.path)
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ExportError.writeFailed(underlying: error)
        }
    }

    private static func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ExportError.writeFailed(underlying: error)
        }
    }
}

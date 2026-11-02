import Foundation
import MarkdownEngine

/// The public entry point for first-party Markdown export.
///
/// Composition is split from writing so tests can inspect the frozen
/// `PreparedExportDocument` without touching the filesystem, and so the app's
/// PDF adapter can reuse the same composition and then print it.
///
/// Export remains local and offline: no resource is fetched over the network,
/// and document content is never transmitted to a hosted renderer.
public enum ExportService {
    public static let moduleName = "ExportService"

    /// Composes an export without writing anything. Throws when the target's
    /// policy cannot be satisfied (e.g. a self-contained export with an
    /// unresolved resource).
    public static func prepare(
        _ request: ExportRequest,
        target: ExportTarget,
        engine: any ParseExecuting = ParseEngine()
    ) async throws -> PreparedExportDocument {
        try await ExportComposer.prepare(request: request, target: target, engine: engine)
    }

    /// Composes and writes an HTML export. Returns the written files and the
    /// composition diagnostics.
    public static func exportHTML(
        _ request: ExportRequest,
        to target: ExportTarget,
        engine: any ParseExecuting = ParseEngine(),
        lease: ExportLifetimeLease = ExportLifetimeLease()
    ) async throws -> ExportResult {
        guard case .html = target else {
            throw ExportError.invalidDestination("exportHTML writes HTML targets only; use the PDF adapter for PDF")
        }
        try lease.checkActive()
        let prepared = try await prepare(request, target: target, engine: engine)
        return try ExportFileWriter.writeHTML(prepared, to: target, lease: lease)
    }

    /// Renders a standalone Markdown fragment to a self-contained HTML
    /// string, independent of any document's metadata/theme/resource
    /// pipeline. Used to turn a contribution's Markdown representation
    /// (e.g. E14's TOC) into the `html` an `ExportDerivedContribution`
    /// requires (epic-14-implementation.md §6.4).
    ///
    /// Returns an empty string on any render failure —
    /// `DerivedContentComposer`'s existing "empty html is rejected,
    /// authored source preserved" rule already handles that gracefully, so
    /// no new failure-handling is needed at this layer.
    ///
    /// Deliberately omits `CMARK_OPT_UNSAFE`: a generated fragment is not
    /// authored top-level content and has no legitimate need to embed raw
    /// HTML, so this is more conservative than the main document pipeline,
    /// not less.
    public static func renderMarkdownFragment(_ markdown: String) -> String {
        (try? CMarkGFM.renderHTML(markdown, options: CMarkGFM.optDefault | CMarkGFM.optSmart)) ?? ""
    }
}

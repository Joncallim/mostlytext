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
        lease: ExportLifetimeLease = ExportLifetimeLease(),
        admission: ExportDestinationAdmission? = nil,
        recovery: ExportRecoveryLocation? = nil
    ) async throws -> ExportResult {
        guard case let .html(url, _) = target else {
            throw ExportError.invalidDestination("exportHTML writes HTML targets only; use the PDF adapter for PDF")
        }
        try lease.checkActive()
        let authorization = try admission ?? ExportDestinationAdmission(
            capturing: url, protecting: request.documentURL.map { [$0] } ?? []
        )
        try authorization.checkTarget(url)
        try authorization.checkNoDocumentAliases(request.documentURL.map { [$0] } ?? [])
        try authorization.checkNoFileAliases(request.protectedSourceIdentity.map { [$0] } ?? [])
        let prepared = try await prepare(request, target: target, engine: engine)
        return try ExportFileWriter.writeHTML(prepared, to: target, admission: authorization, lease: lease,
                                              recovery: recovery)
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

    /// Use the same GFM parser for a passive Quick Look fragment. Links and
    /// images retain their authored labels/alt text but receive no URL, so a
    /// selected file cannot cause a fetch or navigation through this path.
    public static func renderPassiveMarkdownFragment(_ markdown: String) -> String {
        (try? CMarkGFM.renderHTML(
            markdown,
            options: CMarkGFM.optDefault | CMarkGFM.optSmart,
            urlTransformer: { _, _ in .blank }
        )) ?? ""
    }

    /// Compose already-produced static content through Export's source-range
    /// validation and GFM tree walk. A rejected item leaves its authored source
    /// in place. Quick Look supplies only immutable, generation-bound results;
    /// this function never invokes a renderer or grants resource access.
    public static func renderPassiveMarkdownFragment(
        _ markdown: String,
        contributions: [ExportDerivedContribution],
        sourceGeneration: UInt
    ) -> String {
        guard !contributions.isEmpty else { return renderPassiveMarkdownFragment(markdown) }
        // Bound producer output before the sanitizer copies it. These are
        // provisional per-item/aggregate Quick Look limits, below the worker's
        // complete reply cap; a refused item keeps its authored Markdown.
        let singleLimit = 1 << 20
        var remaining = 4 << 20
        let passiveContributions = contributions.compactMap { item -> ExportDerivedContribution? in
            let size = item.html.utf8.count
            guard size <= singleLimit else { return nil }
            let safeHTML = DerivedHTMLSanitizer.sanitized(item.html, urlPolicy: .passive)
            let safeSize = safeHTML.utf8.count
            guard safeSize <= singleLimit, safeSize <= remaining else { return nil }
            remaining -= safeSize
            return ExportDerivedContribution(
                sourceRange: item.sourceRange,
                placement: item.placement,
                html: safeHTML,
                sourceGeneration: item.sourceGeneration,
                diagnostics: item.diagnostics,
                requiresHeadingNavigation: item.requiresHeadingNavigation
            )
        }
        let derived = DerivedContentComposer.compose(
            bodyText: markdown,
            bodyStartOffset: 0,
            sourceUTF16Length: markdown.utf16.count,
            contributions: passiveContributions,
            sourceGeneration: sourceGeneration,
            namespaceSVGIDs: true
        )
        guard let rendered = try? CMarkGFM.render(
            derived.splicedBody,
            options: CMarkGFM.optDefault | CMarkGFM.optSmart,
            customNodes: derived.customNodes,
            urlTransformer: { _, _ in .blank }
        ) else { return "" }
        guard DerivedContentComposer.leakedSentinelIndices(
            in: rendered.html, suffix: derived.sentinelSuffix
        ).isEmpty else { return "" }
        return rendered.html
    }
}

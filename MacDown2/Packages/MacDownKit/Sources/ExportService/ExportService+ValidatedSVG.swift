import Foundation
import MarkdownEngine

extension ExportService {
    /// Disabled opt-in route for generated SVGs. One frozen request is composed,
    /// checked against its destination-specific complete HTML, and published
    /// without handing rejected bytes to the ordinary writer. The app supplies
    /// the PDF printer because ExportService has no AppKit dependency.
    public static func exportValidatedSVG(
        _ request: ExportRequest, to target: ExportTarget,
        lease: ExportLifetimeLease,
        engine: any ParseExecuting = ParseEngine(),
        publishPDF: (@Sendable (ValidatedExportHTML, URL, ExportLifetimeLease) async throws -> Void)? = nil
    ) async throws -> ExportResult {
        try lease.checkActive()
        let validated = try await prepareValidatedSVG(request, to: target, engine: engine)
        try Task.checkCancellation()
        try lease.checkActive()
        switch target {
        case .html:
            return try ExportFileWriter.writeValidatedHTML(validated, lease: lease)
        case let .pdf(url):
            guard let publishPDF else { throw ExportError.invalidDestination("PDF printer is unavailable") }
            try await publishPDF(validated, url, lease)
            return ExportResult(primaryFile: url, companionFiles: [], diagnostics: validated.diagnostics)
        }
    }

    static func prepareValidatedSVG(
        _ request: ExportRequest, to target: ExportTarget,
        engine: any ParseExecuting
    ) async throws -> ValidatedExportHTML {
        guard let audited = SVGAssemblyOwnership.AuditedHeadCSS.builtIn(for: request.theme, target: target) else {
            throw ExportError.validatedPublicationRejected
        }
        let csp = try csp(for: target)
        let initial = try await ExportComposer.prepareWithRoots(
            request: request, target: target, engine: engine, namespaceSVGIDs: true
        )
        try Task.checkCancellation()
        if let publication = try publication(for: initial, target: target, audited: audited, csp: csp) {
            return ValidatedExportHTML(publication: publication, prepared: initial.prepared,
                                       target: target, sourceText: request.text)
        }

        // Exactly one fresh fallback. The source ranges come from the accepted
        // first render, not a search through rewritten HTML or a stale map.
        let rejected = Set(initial.markedSourceRanges)
        guard !rejected.isEmpty else { throw ExportError.validatedPublicationRejected }
        let kept = request.contributions.filter { !rejected.contains($0.sourceRange) }
        let fallbackRequest = ExportRequest(
            text: request.text, sourceGeneration: request.sourceGeneration,
            theme: request.theme, documentURL: request.documentURL,
            resourceAccess: request.resourceAccess, protectedSourceIdentity: request.protectedSourceIdentity,
            parseOptions: request.parseOptions, contributions: kept
        )
        let fallback = try await ExportComposer.prepareWithRoots(
            request: fallbackRequest, target: target, engine: engine, namespaceSVGIDs: true
        )
        try Task.checkCancellation()
        guard fallback.markedRoots.isEmpty,
              let publication = try publication(for: fallback, target: target, audited: audited, csp: csp)
        else { throw ExportError.validatedPublicationRejected }
        let diagnostic = ExportDiagnostic(
            severity: .warning,
            message: String(
                localized: "generated diagram could not be safely isolated; authored source preserved",
                bundle: .module
            )
        )
        return ValidatedExportHTML(
            publication: publication, prepared: fallback.prepared,
            target: target, sourceText: request.text,
            diagnostics: fallback.prepared.diagnostics + [diagnostic]
        )
    }

    private static func publication(
        for output: ExportComposer.MarkedPreparation, target: ExportTarget,
        audited: SVGAssemblyOwnership.AuditedHeadCSS, csp: String
    ) throws -> SVGAssemblyOwnership.Publication? {
        let prepared = output.prepared
        guard prepared.stylesheet == audited.stylesheet else { return nil }
        let body: String
        let html: String
        let head = #"<meta http-equiv="Content-Security-Policy" content="\#(csp)">"#
        switch target {
        case let .html(_, mode):
            switch mode {
            case .selfContained:
                html = try ExportHTMLWriter.selfContainedHTML(from: prepared, additionalHead: head)
                body = try ExportHTMLWriter.selfContainedBody(from: prepared)
            case .standalone(style: .embedded):
                body = prepared.bodyHTML
                html = try ExportHTMLWriter.companionHTML(from: prepared, style: .embedded, additionalHead: head)
            case .standalone(style: .linked):
                return nil
            }
        case .pdf:
            html = try ExportHTMLWriter.selfContainedHTML(from: prepared, additionalHead: head)
            body = try ExportHTMLWriter.selfContainedBody(from: prepared)
        }
        if output.markedRoots.isEmpty {
            return SVGAssemblyOwnership.publishFallback(html, auditedHeadCSS: audited, requiredCSP: csp)
        }
        let fragment = SVGIDNamespace.MarkedFragment(html: body, roots: output.markedRoots)
        guard let inspected = SVGAssemblyOwnership.inspect(
            markedDocument: html, fragment: fragment, auditedHeadCSS: audited, requiredCSP: csp
        ) else { return nil }
        return SVGAssemblyOwnership.publish(markedDocument: html, fragment: fragment, inspected: inspected)
    }

    private static func csp(for target: ExportTarget) throws -> String {
        let common = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
            + "font-src data:; connect-src 'none'; object-src 'none'; "
            + "form-action 'none'; base-uri 'none';"
        switch target {
        case .html(_, .standalone(style: .linked)):
            throw ExportError.validatedPublicationRejected
        case .html(_, .standalone(style: .embedded)):
            return common + " img-src 'self' data:;"
        case .html(_, .selfContained), .pdf:
            return common + " img-src data:;"
        }
    }
}

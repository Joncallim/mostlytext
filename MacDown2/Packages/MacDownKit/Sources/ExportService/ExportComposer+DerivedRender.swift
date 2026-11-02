import Foundation

extension ExportComposer {
    struct DerivedRender {
        let derived: DerivedContentComposer.Result
        let rendered: CMarkGFM.Rendered
        let resolver: ExportResourceResolver
        let leakWarnings: [ExportDiagnostic]
    }

    /// Composes and renders the body. A sentinel cmark could not substitute (inside a link title, a definition, an
    /// attribute…) would otherwise be exported as visible garbage or inside a URL, so when one survives the render
    /// the body is re-composed without exactly those contributions — their authored source stays — and re-rendered
    /// with a fresh resolver (its manifest and diagnostics accumulate per render).
    static func renderDerived(
        request: ExportRequest,
        parsed: ParsedSource,
        policy: Policy,
        assetsDirName: String,
        budget: ExportResourceBudget,
        namespaceSVGIDs: Bool = false
    ) throws -> DerivedRender {
        let sourceLength = request.text.utf16.count
        var derived = composeDerived(request: request, parsed: parsed, budget: budget,
                                     sourceUTF16Length: sourceLength, namespaceSVGIDs: namespaceSVGIDs)
        var (rendered, resolver) = try render(
            derived: derived, policy: policy, assetsDirName: assetsDirName, request: request, budget: budget
        )
        let leaked = DerivedContentComposer.leakedSentinelIndices(in: rendered.html, suffix: derived.sentinelSuffix)
        guard !leaked.isEmpty else { return DerivedRender(
            derived: derived,
            rendered: rendered,
            resolver: resolver,
            leakWarnings: []
        ) }

        let sorted = request.contributions.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
        let kept = sorted.enumerated().filter { !leaked.contains($0.offset) }.map(\.element)
        derived = composeDerived(
            request: request, parsed: parsed, budget: budget, sourceUTF16Length: sourceLength,
            contributions: kept, namespaceSVGIDs: namespaceSVGIDs
        )
        (rendered, resolver) = try render(
            derived: derived, policy: policy, assetsDirName: assetsDirName, request: request, budget: budget
        )
        let warning = ExportDiagnostic(
            severity: .warning,
            message: "\(leaked.count) math or diagram fragment(s) sit inside a link, reference definition or HTML "
                + "construct and cannot be placed there; they are exported as their source text"
        )
        return DerivedRender(derived: derived, rendered: rendered, resolver: resolver, leakWarnings: [warning])
    }

    static func composeDerived(
        request: ExportRequest,
        parsed: ParsedSource,
        budget: ExportResourceBudget,
        sourceUTF16Length: Int,
        contributions: [ExportDerivedContribution]? = nil,
        namespaceSVGIDs: Bool = false
    ) -> DerivedContentComposer.Result {
        DerivedContentComposer.compose(
            bodyText: parsed.bodyText,
            bodyStartOffset: parsed.bodyStartOffset,
            sourceUTF16Length: sourceUTF16Length,
            contributions: contributions ?? request.contributions,
            sourceGeneration: request.sourceGeneration,
            budget: budget,
            containerRanges: parsed.containerRanges,
            recordCoordinates: namespaceSVGIDs,
            namespaceSVGIDs: namespaceSVGIDs
        )
    }

    /// Renders with a FRESH resolver: its manifest and diagnostics accumulate per render.
    static func render(
        derived: DerivedContentComposer.Result,
        policy: Policy,
        assetsDirName: String,
        request: ExportRequest,
        budget: ExportResourceBudget
    ) throws -> (CMarkGFM.Rendered, ExportResourceResolver) {
        let resolver = ExportResourceResolver(
            documentDirectory: request.documentDirectory,
            unresolvedIsFatal: policy.unresolvedResourcesAreFatal,
            budget: budget,
            assetsDirectoryName: assetsDirName
        )
        let registry = ExportResourceURLRegistry(
            avoiding: [request.text, assetsDirName, stylesheet(for: request.theme)] + derived.customNodes.map(\.html),
            assetsDirectoryName: assetsDirName, limit: budget.maxPreparedHTMLUTF8Bytes
        )
        let rendered = try renderBody(derived: derived, policy: policy, resolver: resolver, registry: registry)
        let resolved = try registry.resolve(rendered.html)
        return (CMarkGFM.Rendered(
            html: resolved.html, resourceSlots: resolved.slots, containsRawHTML: rendered.containsRawHTML,
            headingLocations: rendered.headingLocations, headingMarkers: rendered.headingMarkers,
            headingSourceSHA256: rendered.headingSourceSHA256
        ), resolver)
    }
}

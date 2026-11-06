import Foundation
import LocalResourceAccess
import MarkdownEngine

extension ExportComposer {
    /// Keep each retry's registry private until the accepted source map, heading
    /// nodes and final targets agree. Resolving URLs earlier would invalidate
    /// their body digest and byte ranges when heading attributes are inserted.
    static func renderHeadingDerived(
        request: ExportRequest,
        parsed: ParsedSource,
        policy: Policy,
        assetsDirName: String,
        budget: ExportResourceBudget,
        rendering: (namespaceSVGIDs: Bool, cancellation: ResourceCancellation) = (false, ResourceCancellation())
    ) throws -> DerivedRender {
        let (namespaceSVGIDs, cancellation) = rendering
        guard let index = request.headingIndex, index.identity.sourceGeneration == request.sourceGeneration,
              index.identity.parseOptions == request.parseOptions,
              index.headings.count <= HeadingAnchorPreparation.maximumHeadingCount else {
            throw ExportError.headingNavigationUnavailable
        }
        let sourceLength = request.text.utf16.count
        var derived = composeDerived(
            request: request, parsed: parsed, budget: budget,
            sourceUTF16Length: sourceLength, namespaceSVGIDs: namespaceSVGIDs
        )
        var output = try renderUnresolved(
            derived: derived, policy: policy, assetsDirName: assetsDirName, request: request,
            budget: budget, cancellation: cancellation, headingAnalysis: .marked
        )
        guard output.rendered.html.utf8.count <= budget.maxPreparedHTMLUTF8Bytes else {
            throw BoundedExportHTML.tooLarge
        }
        let leaked = DerivedContentComposer.leakedSentinelIndices(
            in: output.rendered.html, suffix: derived.sentinelSuffix
        )
        var warnings: [ExportDiagnostic] = []
        if !leaked.isEmpty {
            try Task.checkCancellation()
            let sorted = request.contributions.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
            let kept = sorted.enumerated().filter { !leaked.contains($0.offset) }.map(\.element)
            derived = composeDerived(
                request: request, parsed: parsed, budget: budget, sourceUTF16Length: sourceLength,
                contributions: kept, namespaceSVGIDs: namespaceSVGIDs
            )
            output = try renderUnresolved(
                derived: derived, policy: policy, assetsDirName: assetsDirName, request: request,
                budget: budget, cancellation: cancellation, headingAnalysis: .marked
            )
            warnings.append(headingSentinelWarning(count: leaked.count))
        }
        try Task.checkCancellation()
        guard output.rendered.html.utf8.count <= budget.maxPreparedHTMLUTF8Bytes else {
            throw BoundedExportHTML.tooLarge
        }
        guard DerivedContentComposer.leakedSentinelIndices(
            in: output.rendered.html, suffix: derived.sentinelSuffix
        ).isEmpty,
            let html = HeadingTargetPublication.publish(
                index: index, document: parsed.document, sourceText: request.text,
                derived: derived, rendered: output.rendered
            ) else { throw ExportError.headingNavigationUnavailable }
        try Task.checkCancellation()
        let resolved = try output.resolving(html: html)
        return DerivedRender(derived: derived, rendered: resolved, resolver: output.resolver, leakWarnings: warnings)
    }

    private static func headingSentinelWarning(count: Int) -> ExportDiagnostic {
        ExportDiagnostic(
            severity: .warning,
            message: String(localized: """
            \(count) math or diagram fragment(s) sit inside a link, reference definition or HTML construct \
            and cannot be placed there; they are exported as their source text
            """, bundle: .module)
        )
    }
}

enum HeadingTargetPublication {
    static func publish(
        index: HeadingAnchorIndex, document: MarkdownDocument, sourceText: String,
        derived: DerivedContentComposer.Result, rendered: CMarkGFM.Rendered
    ) -> String? {
        guard document.isBound(to: sourceText), let matches = EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: sourceText, derived: derived, rendered: rendered
        ) else { return nil }
        // The no-heading placeholder generates no links or target authority.
        if matches.isEmpty {
            return rendered.html
        }
        // Cmark emits no IDs from raw-free Markdown. Only its accepted custom
        // HTML nodes can change that property or the HTML parsing context.
        let direct = !rendered.containsRawHTML && derived.customNodes.allSatisfy {
            HeadingFragmentStructure.accepts($0.html, isBlock: $0.isBlock)
        }
        guard direct else {
            guard let inspected = EmittedHeadingDOM.inspect(rendered) else { return nil }
            return EmittedHeadingDOM.publish(inspected: inspected, rendered: rendered, matches: matches)
        }
        let fragments = matches.map { Data($0.indexed.fragment.utf8) }
        guard Set(fragments).count == fragments.count,
              matches.count == rendered.headingMarkers.count else { return nil }
        var replacements: [String: (level: Int, fragment: String)] = [:]
        for (match, marker) in zip(matches, rendered.headingMarkers) {
            guard match.emitted == marker.location,
                  replacements.updateValue(
                      (level: marker.location.level, fragment: match.indexed.fragment), forKey: marker.comment
                  ) == nil else { return nil }
        }
        return EmittedHeadingDOM.patchMarkedHeadings(rendered.html, replacements: replacements)
    }
}

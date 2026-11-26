import Contributions
import ExportService
import FileCore
import Foundation
import MarkdownEngine
import Preview

/// Turns contribution results into extra/replacement `PreviewBlock`s for
/// `DocumentEditorSplitView`'s preview pane (epic-14-implementation.md §6.6,
/// §7.1). A pure, stateless namespace: every dependency is an explicit
/// parameter — no `FileDocument`, parse session, SwiftUI state, or the
/// filesystem — so admission, placement, budget, and diagnostic behavior are
/// directly unit-testable (architecture takeover, "Shared Preview
/// composition seam"). See `PreviewContributionAdmission.swift` and
/// `PreviewContributionComposer.swift` for the pipeline this delegates to.
enum PreviewContributionAdapter {
    enum HeadingState: Sendable {
        case preparing
        case unavailable
        case prepared(HeadingAnchorPreparation)
    }

    /// Runs the standard contribution registry for one document snapshot.
    /// Cancellation, and any other thrown error, propagates to the caller —
    /// this never converts a cancelled or failed run into an empty result
    /// set (architecture pass 8/10).
    static func results(
        document: MarkdownDocument?,
        text: String?,
        generation: UInt,
        headingState: HeadingState? = nil,
        locale: Locale = .current
    ) async throws -> [ContributionResult] {
        guard let document, let text else { return [] }
        let registry: ContributionRegistry
        switch headingState {
        case nil: registry = .standard(locale: locale)
        case .preparing: return []
        case .unavailable:
            guard TOCContribution.containsMarker(in: text, document: document) else { return [] }
            let diagnostic = ContributionDiagnostic(
                severity: .error,
                message: TOCContribution.navigationUnavailableMessage(locale: locale)
            )
            let result = ContributionResult(
                contributionID: "toc", content: nil, sourceGeneration: generation, diagnostics: [diagnostic]
            )
            return [result]
        case let .prepared(preparation):
            registry = ContributionRegistry(
                contributions: [TOCContribution(headingIndex: preparation.index, locale: locale)],
                locale: locale
            )
        }
        return try await registry.run(
            document: document, sourceText: text, sourceGeneration: generation
        )
    }

    /// Composes `base` with every placeable contribution spliced in, source
    /// order preserved. Pure: given the same arguments, always returns the
    /// same composition.
    static func compose(
        base: [PreviewBlock],
        document: MarkdownDocument,
        sourceText: String,
        contributions: [ContributionResult],
        sourceGeneration: UInt,
        budget: PreviewContributionBudget = .standard,
        locale: Locale = .current
    ) -> PreviewContributionComposition {
        guard !contributions.isEmpty else {
            return PreviewContributionComposition(sourceGeneration: sourceGeneration, blocks: base, diagnostics: [])
        }

        let sourceUTF16Length = (sourceText as NSString).length
        let (intervals, isCoherent) = baseIntervals(for: base, sourceMap: document.sourceMap)
        var diagnostics = contributions.flatMap(producerDiagnostics(for:))

        guard isCoherent else {
            diagnostics.append(unorderedBlocksDiagnostic(locale: locale))
            return PreviewContributionComposition(
                sourceGeneration: sourceGeneration,
                blocks: base,
                diagnostics: diagnostics
            )
        }

        let context = PreviewCompositionContext(
            base: base, baseIntervals: intervals, document: document, sourceText: sourceText,
            sourceUTF16Length: sourceUTF16Length, sourceGeneration: sourceGeneration, locale: locale
        )
        let (candidates, admissionDiagnostics) = admitAll(contributions, context: context)
        diagnostics.append(contentsOf: admissionDiagnostics)

        let (accepted, resolutionDiagnostics) = resolveOverlapAndBudget(
            candidates: candidates, budget: budget, locale: locale
        )
        diagnostics.append(contentsOf: resolutionDiagnostics)

        guard let composedBlocks = composeBlocks(
            base: base, baseIntervals: intervals, accepted: accepted, sourceText: sourceText,
            sourceMap: document.sourceMap
        ) else {
            let bundle = ViewLocalizationBundle.resolve(locale: locale, in: .main)
            diagnostics.append(PreviewContributionDiagnostic(
                contributionID: "preview-composer", severity: .error,
                message: String(
                    localized: "internal composition invariant violated; contributions left as authored source",
                    bundle: bundle, locale: locale
                )
            ))
            return PreviewContributionComposition(
                sourceGeneration: sourceGeneration,
                blocks: base,
                diagnostics: diagnostics
            )
        }

        return PreviewContributionComposition(
            sourceGeneration: sourceGeneration,
            blocks: composedBlocks,
            diagnostics: diagnostics
        )
    }

    private static func unorderedBlocksDiagnostic(locale: Locale) -> PreviewContributionDiagnostic {
        PreviewContributionDiagnostic(
            contributionID: "preview-composer", severity: .error,
            message: String(
                localized: "preview blocks are not ordered/non-overlapping; contributions left as authored source",
                bundle: ViewLocalizationBundle.resolve(locale: locale, in: .main), locale: locale
            )
        )
    }

    private static func admitAll(
        _ contributions: [ContributionResult],
        context: PreviewCompositionContext
    ) -> (candidates: [PreviewContributionCandidate], diagnostics: [PreviewContributionDiagnostic]) {
        var candidates: [PreviewContributionCandidate] = []
        var diagnostics: [PreviewContributionDiagnostic] = []
        for (index, result) in contributions.enumerated() {
            switch admit(result: result, resultIndex: index, context: context) {
            case .skipped:
                break
            case let .accepted(candidate):
                candidates.append(candidate)
            case let .rejected(message):
                diagnostics.append(PreviewContributionDiagnostic(
                    contributionID: result.contributionID, severity: .error, message: message
                ))
            }
        }
        return (candidates, diagnostics)
    }
}

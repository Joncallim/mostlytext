import Contributions
import FileCore
import Foundation
import MarkdownEngine
import Preview

/// The strict, ordered admission pipeline (architecture takeover, "Strict
/// admission pipeline"): every rejection preserves the authored source and
/// reports a stable adapter diagnostic instead of silently dropping or
/// mis-placing content.
extension PreviewContributionAdapter {
    /// The per-block UTF-16 interval covered by each element of `base`, and
    /// whether those intervals are themselves ordered and non-overlapping —
    /// a precondition every candidate's containment check depends on.
    static func baseIntervals(
        for base: [PreviewBlock],
        sourceMap: SourceMap
    ) -> (intervals: [Range<Int>], isCoherent: Bool) {
        var intervals: [Range<Int>] = []
        var previousUpperBound = 0
        var isCoherent = true
        for block in base {
            let nsRange = sourceMap.utf16Range(ofLines: block.lineRange)
            let interval = nsRange.location ..< (nsRange.location + nsRange.length)
            if interval.lowerBound < previousUpperBound || interval.lowerBound > interval.upperBound {
                isCoherent = false
            }
            intervals.append(interval)
            previousUpperBound = interval.upperBound
        }
        return (intervals, isCoherent)
    }

    /// Diagnostics carried by `result`, forwarded regardless of whether its
    /// content ends up placeable (architecture pass 9/10).
    static func producerDiagnostics(for result: ContributionResult) -> [PreviewContributionDiagnostic] {
        result.diagnostics.map {
            PreviewContributionDiagnostic(
                contributionID: result.contributionID, severity: $0.severity, message: $0.message
            )
        }
    }

    static func admit(
        result: ContributionResult,
        resultIndex: Int,
        context: PreviewCompositionContext
    ) -> PreviewAdmissionOutcome {
        let bundle = ViewLocalizationBundle.resolve(locale: context.locale, in: .main)
        guard let content = result.content else { return .skipped }
        guard !result.diagnostics.contains(where: { $0.severity == .error }) else { return .skipped }
        guard result.sourceGeneration == context.sourceGeneration else {
            return .rejected(String(localized: "\(result.contributionID) is stale; authored source preserved",
                                    bundle: bundle, locale: context.locale))
        }
        guard case .accepted = content.representation.admission(to: .nativePreview) else {
            return .rejected(rejectedHTMLMessage(contributionID: result.contributionID, locale: context.locale))
        }
        guard case let .markdown(markdown) = content.representation else {
            return .rejected(rejectedHTMLMessage(contributionID: result.contributionID, locale: context.locale))
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected(
                String(localized: "\(result.contributionID) produced empty content; authored source preserved",
                       bundle: bundle, locale: context.locale)
            )
        }
        guard context.document.sourceMap.utf16Length == context.sourceUTF16Length else {
            return .rejected(rejectedDocumentMismatchMessage(contributionID: result.contributionID,
                                                             locale: context.locale))
        }

        let range = content.sourceRange
        guard range.lowerBound >= 0, range.upperBound > range.lowerBound,
              range.upperBound <= context.sourceUTF16Length
        else {
            return .rejected(
                String(localized: "\(result.contributionID) has an invalid source range; authored source preserved",
                       bundle: bundle, locale: context.locale)
            )
        }
        guard let blockIndex = containingBlockIndex(for: range, in: context.baseIntervals) else {
            return .rejected(rejectedRangeNotInBlockMessage(contributionID: result.contributionID,
                                                            locale: context.locale))
        }
        if let reason = placementRejectionReason(
            content: content, markdown: markdown, containingBlock: context.base[blockIndex],
            containingInterval: context.baseIntervals[blockIndex], context: context
        ) {
            return .rejected(String(localized: "\(result.contributionID) \(reason); authored source preserved",
                                    bundle: bundle, locale: context.locale))
        }

        return .accepted(PreviewContributionCandidate(
            resultIndex: resultIndex, contributionID: result.contributionID, sourceRange: range,
            placement: content.placement, markdown: markdown, containingBlockIndex: blockIndex
        ))
    }

    private static func rejectedHTMLMessage(contributionID: String, locale: Locale) -> String {
        String(
            localized: "\(contributionID) produced HTML, which Preview does not support; authored source preserved",
            bundle: ViewLocalizationBundle.resolve(locale: locale, in: .main), locale: locale
        )
    }

    private static func rejectedDocumentMismatchMessage(contributionID: String, locale: Locale) -> String {
        String(
            localized: "\(contributionID)'s document does not match the current source; authored source preserved",
            bundle: ViewLocalizationBundle.resolve(locale: locale, in: .main), locale: locale
        )
    }

    private static func rejectedRangeNotInBlockMessage(contributionID: String, locale: Locale) -> String {
        String(
            localized: """
            \(contributionID)'s range does not fall inside exactly one preview block; authored source preserved
            """,
            bundle: ViewLocalizationBundle.resolve(locale: locale, in: .main), locale: locale
        )
    }

    /// `^[...](inflect: true)` only resolves its singular/plural agreement
    /// through `AttributedString`'s markdown-attributed parsing — `String(localized:)`
    /// returns the markup unresolved. `PreviewContributionDiagnostic.message`
    /// is a plain `String` shown via `Text(verbatim:)`, so the count-correct
    /// text must be resolved here, once, before it is stored.
    private static func omittedPlacementsMessage(count: Int, locale: Locale) -> AttributedString {
        AttributedString(
            localized: """
            ^[\(count) valid placement](inflect: true) exceeded the preview budget \
            and remain as authored source
            """,
            bundle: ViewLocalizationBundle.resolve(locale: locale, in: .main), locale: locale
        )
    }

    /// The one base interval fully containing `range`, or `nil` when zero or
    /// more than one does — a range in a newline gap, crossing two blocks,
    /// or outside all blocks is invalid either way.
    private static func containingBlockIndex(for range: Range<Int>, in baseIntervals: [Range<Int>]) -> Int? {
        let matches = baseIntervals.indices.filter { index in
            baseIntervals[index].lowerBound <= range.lowerBound && range.upperBound <= baseIntervals[index].upperBound
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// `nil` when `content`'s placement is admissible; otherwise the reason
    /// it is not (architecture pass 5/10).
    private static func placementRejectionReason(
        content: ContributionContent,
        markdown: String,
        containingBlock: PreviewBlock,
        containingInterval: Range<Int>,
        context: PreviewCompositionContext
    ) -> String? {
        let range = content.sourceRange
        switch content.placement {
        case .inline:
            let replaced = (context.sourceText as NSString).substring(
                with: NSRange(location: range.lowerBound, length: range.count)
            )
            guard !replaced.contains("\n"), !replaced.contains("\r"),
                  !markdown.contains("\n"), !markdown.contains("\r")
            else {
                return String(localized: "has an inline placement that is not confined to one physical line",
                              bundle: ViewLocalizationBundle.resolve(locale: context.locale, in: .main),
                              locale: context.locale)
            }
            return nil
        case .block:
            if range == containingInterval {
                return nil
            }
            guard case .paragraph = containingBlock.kind else {
                return String(localized: "has a partial block placement outside a top-level paragraph",
                              bundle: ViewLocalizationBundle.resolve(locale: context.locale, in: .main),
                              locale: context.locale)
            }
            let sourceMap = context.document.sourceMap
            let startLine = sourceMap.line(atUTF16Offset: range.lowerBound)
            let endLine = sourceMap.line(atUTF16Offset: range.upperBound - 1)
            let exact = sourceMap.utf16Range(ofLines: startLine ... endLine)
            guard exact.location == range.lowerBound, exact.location + exact.length == range.upperBound else {
                return String(localized: "has a partial block placement that does not align with whole physical lines",
                              bundle: ViewLocalizationBundle.resolve(locale: context.locale, in: .main),
                              locale: context.locale)
            }
            return nil
        }
    }

    /// Resolves overlap first (first candidate in source order wins; a later
    /// overlapping one is rejected without consuming budget), then applies
    /// the Preview budget only to the surviving, non-overlapping candidates
    /// (architecture pass 7/10).
    static func resolveOverlapAndBudget(
        candidates: [PreviewContributionCandidate],
        budget: PreviewContributionBudget,
        locale: Locale = .current
    ) -> (accepted: [PreviewContributionCandidate], diagnostics: [PreviewContributionDiagnostic]) {
        let sorted = candidates.sorted {
            $0.sourceRange.lowerBound == $1.sourceRange.lowerBound
                ? $0.resultIndex < $1.resultIndex
                : $0.sourceRange.lowerBound < $1.sourceRange.lowerBound
        }

        var nonOverlapping: [PreviewContributionCandidate] = []
        var diagnostics: [PreviewContributionDiagnostic] = []
        var previousUpperBound = Int.min
        for candidate in sorted {
            guard candidate.sourceRange.lowerBound >= previousUpperBound else {
                diagnostics.append(PreviewContributionDiagnostic(
                    contributionID: candidate.contributionID, severity: .warning,
                    message: String(
                        localized: "\(candidate.contributionID) overlaps another placement; authored source preserved",
                        bundle: ViewLocalizationBundle.resolve(locale: locale, in: .main), locale: locale
                    )
                ))
                continue
            }
            nonOverlapping.append(candidate)
            previousUpperBound = candidate.sourceRange.upperBound
        }

        let (accepted, omittedByBudget) = applyBudget(nonOverlapping, budget: budget)
        if omittedByBudget > 0 {
            diagnostics.append(PreviewContributionDiagnostic(
                contributionID: "preview-budget", severity: .warning,
                message: String(omittedPlacementsMessage(count: omittedByBudget, locale: locale).characters)
            ))
        }
        return (accepted, diagnostics)
    }

    private static func applyBudget(
        _ candidates: [PreviewContributionCandidate],
        budget: PreviewContributionBudget
    ) -> (accepted: [PreviewContributionCandidate], omittedCount: Int) {
        var accepted: [PreviewContributionCandidate] = []
        var aggregateBytes = 0
        var omitted = 0
        for candidate in candidates {
            guard accepted.count < budget.maximumAcceptedPlacements else {
                omitted += 1
                continue
            }
            let (total, overflowed) = aggregateBytes.addingReportingOverflow(candidate.markdown.utf8.count)
            guard !overflowed, total <= budget.maximumGeneratedMarkdownUTF8Bytes else {
                omitted += 1
                continue
            }
            aggregateBytes = total
            accepted.append(candidate)
        }
        return (accepted, omitted)
    }
}

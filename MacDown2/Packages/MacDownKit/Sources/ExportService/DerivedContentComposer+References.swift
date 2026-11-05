import Foundation
import MarkdownEngine

extension DerivedContentComposer {
    struct ReferenceContext {
        let source: String
        let facts: MarkdownSourceFacts
    }

    static var referenceRepairFailure: String {
        String(
            localized: "Derived content could not preserve reference links; authored source was kept.",
            bundle: .module
        )
    }

    /// Suffix edits keep implicit keys original while the existing custom-node
    /// pipeline replaces label content. All edits participate in coordinate mapping.
    static func preservingReferences(
        _ splices: [Splice], bodyText: String, context validation: ValidationContext,
        referenceContext: ReferenceContext?
    ) throws -> [Splice] {
        guard let context = referenceContext, !splices.isEmpty else { return splices }
        let bodyStartOffset = validation.bodyStartOffset
        let original = context.source as NSString
        guard original.length == validation.sourceUTF16Length, bodyStartOffset >= 0, bodyStartOffset <= original.length,
              context.source.utf16.dropFirst(bodyStartOffset).elementsEqual(bodyText.utf16) else {
            throw MarkdownReferenceRepair.Failure.sourceMismatch
        }
        let originalRanges = splices
            .map { ($0.range.lowerBound + bodyStartOffset) ..< ($0.range.upperBound + bodyStartOffset) }
        let repairs = try MarkdownReferenceRepair.edits(source: context.source, facts: context.facts,
                                                        replacing: originalRanges)
        guard !repairs.isEmpty else { return splices }
        let all = (splices + repairs.map { edit in
            Splice(
                range: (edit.sourceRange.lowerBound - bodyStartOffset) ..<
                    (edit.sourceRange.upperBound - bodyStartOffset),
                sentinel: edit.replacement,
                isBlock: false
            )
        }).sorted { $0.range.lowerBound < $1.range.lowerBound }
        try validateReferenceSplices(all, bodyText: bodyText, budget: validation.budget)
        return all
    }

    private static func validateReferenceSplices(
        _ splices: [Splice], bodyText: String, budget: ExportResourceBudget
    ) throws {
        let body = bodyText as NSString
        var previousEnd = 0
        var bytes = bodyText.utf8.count
        for splice in splices {
            guard splice.range.lowerBound >= previousEnd, !splice.range.isEmpty,
                  splice.range.upperBound <= body.length else { throw MarkdownReferenceRepair.Failure.invalidRange }
            let removed = body.substring(with: NSRange(location: splice.range.lowerBound, length: splice.range.count))
            let (total, overflow) = bytes.addingReportingOverflow(splice.renderedText.utf8.count - removed.utf8.count)
            guard !overflow else { throw MarkdownReferenceRepair.Failure.invalidRange }
            bytes = total
            previousEnd = splice.range.upperBound
        }
        guard bytes <= budget.maxPreparedHTMLUTF8Bytes else { throw MarkdownReferenceRepair.Failure.invalidRange }
    }
}

import Foundation
import MarkdownEngine
import MathSyntax

/// One source-bound structural admission, shared by future Preview/Export adapters.
/// This pure synchronous work belongs on the caller's bounded analysis worker.
public struct MathAnalysis: Sendable, Equatable {
    public let sourceIdentity: MathSourceIdentity
    public let sourceSHA256: String
    public let revision: Int
    public let equations: [MathEquation]
    public let literalRemainderOffset: Int?

    public static func analyze(
        source: String, document: MarkdownDocument, sourceIdentity: MathSourceIdentity,
        maximumSpanCount: Int
    ) throws -> MathAnalysis {
        try Task.checkCancellation()
        guard let digest = document.sourceSHA256 else { throw MathAnalysisError.unboundDocument }
        guard document.isBound(to: source) else { throw MathAnalysisError.sourceMismatch }
        guard let facts = document.sourceFacts else { throw MathAnalysisError.sourceFactsUnavailable }
        guard facts.sourceSHA256 == digest else { throw MathAnalysisError.sourceMismatch }
        try Task.checkCancellation()
        let scanned = try MathTokenizer.scan(
            source, identity: sourceIdentity, regions: facts.inlineRegions,
            exclusions: exclusions(facts), maximumSpanCount: maximumSpanCount
        )
        var projector = MathExpressionProjection(units: Array(source.utf16), prefixes: facts.continuationPrefixes)
        var equations: [MathEquation] = []
        for span in scanned.spans {
            try Task.checkCancellation()
            let projection = try projector.project(body: span.bodyRange)
            equations.append(MathEquation(
                id: MathOccurrenceIdentity.make(span: span, sourceSHA256: digest), syntax: span,
                rendererExpression: projection.expression, expressionSegments: projection.segments
            ))
        }
        try Task.checkCancellation()
        return MathAnalysis(sourceIdentity: sourceIdentity, sourceSHA256: digest, revision: document.revision,
                            equations: equations, literalRemainderOffset: scanned.literalRemainderOffset)
    }

    private static func exclusions(_ facts: MarkdownSourceFacts) -> [Range<Int>] {
        var result = facts.literalRanges
        for link in facts.links {
            if let label = link.labelRange {
                result.append(link.fullRange.lowerBound ..< label.lowerBound)
                result.append(label.upperBound ..< link.fullRange.upperBound)
            } else {
                result.append(link.fullRange)
            }
        }
        return result
    }
}

public enum MathAnalysisError: Error, Equatable {
    case unboundDocument
    case sourceMismatch
    case sourceFactsUnavailable
    case invalidPrefixMapping
}

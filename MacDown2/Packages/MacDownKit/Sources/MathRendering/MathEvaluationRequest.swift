import Foundation
import MarkdownEngine
import Math
import MathSyntax
import SwiftUIMath

/// An immutable analysis request. The caller retains this identity across await
/// and checks its generation/lifetime against the live document before publication.
public struct MathEvaluationRequest: Sendable, Identifiable {
    public let id: UUID
    public let source: String
    public let document: MarkdownDocument
    public let sourceIdentity: MathSourceIdentity
    public let generation: UInt64
    public let maximumSpanCount: Int
    public let bodyLimits: SwiftUIMath.Math.BodyLimits

    public init(
        source: String, document: MarkdownDocument, sourceIdentity: MathSourceIdentity,
        generation: UInt64, maximumSpanCount: Int, bodyLimits: SwiftUIMath.Math.BodyLimits
    ) {
        id = UUID()
        self.source = source
        self.document = document
        self.sourceIdentity = sourceIdentity
        self.generation = generation
        self.maximumSpanCount = maximumSpanCount
        self.bodyLimits = bodyLimits
    }

    func evaluate() throws -> MathEvaluation {
        let analysis = try MathAnalysis.analyze(
            source: source, document: document, sourceIdentity: sourceIdentity, maximumSpanCount: maximumSpanCount
        )
        return try MathEvaluation.evaluate(analysis: analysis, limits: bodyLimits)
    }
}

import Foundation
import MarkdownEngine
import Math

/// A common cap boundary prevents either destination from reinterpreting an
/// unscanned tail or partially typesetting the block that contains that tail.
public struct MathPresentationPlan: Sendable {
    public let entries: [MathEvaluation.Entry]
    public let literalRemainderRange: Range<Int>?
    public let literalRemainderID: UUID?

    public init(evaluation: MathEvaluation, document: MarkdownDocument) throws {
        guard evaluation.analysis.sourceSHA256 == document.sourceSHA256,
              evaluation.analysis.revision == document.revision else { throw MathAnalysisError.sourceMismatch }
        guard let unscanned = evaluation.analysis.literalRemainderOffset,
              unscanned < document.sourceMap.utf16Length else {
            entries = evaluation.entries
            literalRemainderRange = nil
            literalRemainderID = nil
            return
        }
        let bodyStart = document.sourceMap.utf16Length - document.body.utf16.count
        let tail = max(bodyStart, unscanned)
        let line = document.sourceMap.line(atUTF16Offset: tail)
        let blockStart = document.blocks.first { $0.lineRange.contains(line) }.map {
            document.sourceMap.utf16Range(ofLines: $0.lineRange).location
        } ?? document.sourceMap.lineStartOffsets[line - 1]
        let start = max(bodyStart, min(tail, blockStart))
        entries = evaluation.entries.filter { $0.equation.syntax.fullRange.upperBound <= start }
        literalRemainderRange = start ..< document.sourceMap.utf16Length
        literalRemainderID = UUID()
    }
}

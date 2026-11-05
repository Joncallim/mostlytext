import Foundation
import MarkdownEngine
@testable import Math
import Testing

struct MathExpressionMappingTests {
    @Test func mappingRejectsSurrogateAndCRLFInteriorsAndOutsideOffsets() async throws {
        let source = "> $$😀\r\n>   +y$$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let result = try MathAnalysis.analyze(source: source, document: document,
                                              sourceIdentity: .init(rawValue: UUID()), maximumSpanCount: 256)
        let equation = try #require(result.equations.first)
        #expect(equation.rendererExpression == "😀\r\n+y")
        #expect(equation.sourceOffset(forRenderedUTF16Offset: -1) == nil)
        #expect(equation.sourceOffset(forRenderedUTF16Offset: 1) == nil)
        #expect(equation.sourceOffset(forRenderedUTF16Offset: 3) == nil)
        #expect(equation.sourceOffset(forRenderedUTF16Offset: 7) == nil)
        let expected = (source as NSString).range(of: "+y", options: .literal).location
        #expect(equation.sourceOffset(forRenderedUTF16Offset: 4) == expected)
        #expect(equation.sourceOffset(forRenderedUTF16Offset: 6) == equation.syntax.bodyRange.upperBound)
    }

    @Test func prefixBodyPartialOverlapFailsInsteadOfTrimmingAnUnknownRange() {
        for prefix in [1 ..< 4, 4 ..< 7] {
            var projection = MathExpressionProjection(units: Array("abcdefghi".utf16), prefixes: [prefix])
            #expect(throws: MathAnalysisError.invalidPrefixMapping) { try projection.project(body: 2 ..< 5) }
        }
    }

    @Test func aPrefixCannotRemoveAuthoredTeXNewlinesOrHalfASurrogate() {
        let cases = [("abcdef", 2 ..< 3), ("a\n>b", 1 ..< 3), ("a\r\n>b", 1 ..< 4), ("a😀b", 1 ..< 2)]
        for (source, prefix) in cases {
            var projection = MathExpressionProjection(units: Array(source.utf16), prefixes: [prefix])
            #expect(throws: MathAnalysisError.invalidPrefixMapping) {
                try projection.project(body: 0 ..< source.utf16.count)
            }
        }
    }

    @Test func nonASCIIAuthoredBytesRemainExactThroughProjection() async throws {
        let expression = "e\u{301}+漢+😀"
        let source = "$" + expression + "$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let analysis = try MathAnalysis.analyze(source: source, document: document,
                                                sourceIdentity: .init(rawValue: UUID()), maximumSpanCount: 256)
        let equation = try #require(analysis.equations.first)
        #expect(equation.rendererExpression.utf8.elementsEqual(expression.utf8))
        #expect(equation.syntax.expression.utf8.elementsEqual(expression.utf8))
        #expect(equation.expressionSegments.count == 1)
        #expect(equation.expressionSegments.first?.sourceRange == 1 ..< source.utf16.count - 1)
    }
}

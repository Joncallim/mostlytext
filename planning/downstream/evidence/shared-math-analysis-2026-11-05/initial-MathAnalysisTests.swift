import Foundation
import MarkdownEngine
@testable import Math
import MathSyntax
import Testing

struct MathAnalysisTests {
    private let identity = MathSourceIdentity(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID())

    private func analyze(_ source: String, maximum: Int = 256) async throws -> MathAnalysis {
        let document = try await ParseEngine().parse(source, revision: 7)
        return try MathAnalysis.analyze(source: source, document: document, sourceIdentity: identity,
                                        maximumSpanCount: maximum)
    }

    private func authored(_ source: String, range: Range<Int>) -> String {
        String(decoding: Array(source.utf16)[range], as: UTF16.self)
    }

    @Test func currencyEscapesAndRecoveryUseTheSharedOriginalGrammar() async throws {
        let source = #"Prices $5 and $10; then \$literal and $x$. Even \$y$; $z$2 and $ good$"#
        let result = try await analyze(source)
        #expect(result.equations.map(\.rendererExpression) == ["x", "y"])
        #expect(result.equations.map { authored(source, range: $0.syntax.fullRange) } == ["$x$", "$y$"])
        #expect(result.revision == 7)
        #expect(result.sourceIdentity == identity)
    }

    @Test func literalCodeTagsImagesAndAutolinksAreNotAdmitted() async throws {
        let source = "`$code$` <span title='$attribute$'>$real$</span> ![alt $image$](/img) <https://example.com/$url$>"
        let result = try await analyze(source)
        #expect(result.equations.map(\.rendererExpression) == ["real"])
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func nestedFencesAndReferenceDefinitionsStayLiteral(ending: String) async throws {
        let source = ["> - ```tex", ">   $not$", ">", ">   $alsoNot$", ">   ```", "",
                      "[key]: /$destination$", "", "[$real$][key]"].joined(separator: ending)
        let result = try await analyze(source)
        #expect(result.equations.map(\.rendererExpression) == ["real"])
    }

    @Test func linkLabelsAreIndependentFromDestinationsAndSurroundingText() async throws {
        let source = "$[x](y)$ and [$z$](/$destination$) and [$r$][]\n\n[$r$]: /target \"title\""
        let result = try await analyze(source)
        #expect(result.equations.map(\.rendererExpression) == ["z", "r"])
        #expect(result.equations.map { authored(source, range: $0.syntax.fullRange) } == ["$z$", "$r$"])
    }

    @Test func tableCellsAndBlocksCannotPairTheirPartialDelimiters() async throws {
        let source = "before $partial\n\n| A | B |\n|---|---|\n| $a | b$ |\n\n$real$"
        let result = try await analyze(source)
        #expect(result.equations.map(\.rendererExpression) == ["real"])
    }

    @Test func completeEquationsInParagraphAndTableRetainTheirOwnRanges() async throws {
        let source = "漢😀 $p$\n| $h$ | B |\n|---|---|\n| $x$ | $y$ |"
        let result = try await analyze(source)
        #expect(result.equations.map(\.rendererExpression) == ["p", "h", "x", "y"])
        #expect(result.equations.map { authored(source, range: $0.syntax.fullRange) } == ["$p$", "$h$", "$x$", "$y$"])
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func rendererProjectionPreservesCommentsNewlinesAndGenuineOperators(ending: String) async throws {
        let source = "> - $$a😀 % comment" + ending + ">   +b > c$$"
        let result = try await analyze(source)
        let equation = try #require(result.equations.first)
        #expect(equation.syntax.expression.utf8.elementsEqual(("a😀 % comment" + ending + ">   +b > c").utf8))
        #expect(equation.rendererExpression.utf8.elementsEqual(("a😀 % comment" + ending + "+b > c").utf8))
        #expect(equation.expressionSegments.count == 2)
        let renderedOffset = (equation.rendererExpression as NSString).range(of: "+b", options: .literal).location
        let sourceOffset = (source as NSString).range(of: "+b", options: .literal).location
        #expect(equation.sourceOffset(forRenderedUTF16Offset: renderedOffset) == sourceOffset)
        #expect(equation.sourceOffset(forRenderedUTF16Offset: equation.rendererExpression.utf16.count) ==
            equation.syntax.bodyRange.upperBound)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func variableAndLazyPrefixesDoNotStealActualExpressionCharacters(ending: String) async throws {
        for second in [">     +y$$", "+y$$"] {
            let source = "> $$x" + ending + second
            let equation = try #require(try await analyze(source).equations.first)
            #expect(equation.rendererExpression.utf8.elementsEqual(("x" + ending + "+y").utf8))
        }
    }

    @Test func explicitCapsLeaveTheUnscannedSourceLiteral() async throws {
        let source = "$a$ $b$ $c$"
        let one = try await analyze(source, maximum: 1)
        #expect(one.equations.map(\.rendererExpression) == ["a"])
        #expect(one.literalRemainderOffset == 3)
        let zero = try await analyze(source, maximum: 0)
        #expect(zero.equations.isEmpty)
        #expect(zero.literalRemainderOffset == 0)
        #expect(try await analyze(source).literalRemainderOffset == nil)
    }

    @Test func negativeCapsAreRejected() async throws {
        await #expect(throws: MathSyntaxError.invalidMaximumSpanCount) {
            _ = try await analyze("$x$", maximum: -1)
        }
    }

    @Test func occurrenceIdentityIsStableDistinctAndBoundToSourceLifetime() async throws {
        let source = "$x$ then $x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let first = try MathAnalysis.analyze(source: source, document: document, sourceIdentity: identity,
                                              maximumSpanCount: 256)
        let repeated = try MathAnalysis.analyze(source: source, document: document, sourceIdentity: identity,
                                                 maximumSpanCount: 256)
        let other = try MathAnalysis.analyze(source: source, document: document,
                                              sourceIdentity: .init(rawValue: UUID()), maximumSpanCount: 256)
        #expect(first.equations.map(\.id) == repeated.equations.map(\.id))
        #expect(Set(first.equations.map(\.id)).count == 2)
        #expect(Set(first.equations.map(\.id)).isDisjoint(with: other.equations.map(\.id)))
        let changed = try await analyze("$y$ then $y$")
        #expect(Set(first.equations.map(\.id)).isDisjoint(with: changed.equations.map(\.id)))
    }

    @Test func canonicallyEqualSourceCannotBorrowCoordinateAuthority() async throws {
        let original = "e\u{301} $x$", other = "é $x$"
        #expect(original == other)
        let document = try await ParseEngine().parse(original, revision: 1)
        #expect(document.isBound(to: original))
        #expect(!document.isBound(to: other))
        #expect(throws: MathAnalysisError.sourceMismatch) {
            try MathAnalysis.analyze(source: other, document: document, sourceIdentity: identity, maximumSpanCount: 256)
        }
    }

    @Test func unboundAndSanitizedSourceCannotCreateGuessedEquations() async throws {
        let source = "$x$"
        let unbound = MarkdownDocument(body: source, bodyLineOffset: 0, blocks: [], headings: [], frontMatter: nil,
                                       sourceMap: SourceMap(text: source), revision: 1, options: .default)
        #expect(!unbound.isBound(to: source))
        #expect(throws: MathAnalysisError.unboundDocument) {
            try MathAnalysis.analyze(source: source, document: unbound, sourceIdentity: identity, maximumSpanCount: 256)
        }
        let nul = "before\u{0} $x$"
        let document = try await ParseEngine().parse(nul, revision: 1)
        #expect(throws: MathAnalysisError.sourceFactsUnavailable) {
            try MathAnalysis.analyze(source: nul, document: document, sourceIdentity: identity, maximumSpanCount: 256)
        }
    }

    @Test func cancellationWinsBeforeAnySourceAdmission() async throws {
        let source = "$x$", document = try await ParseEngine().parse("$x$", revision: 1)
        let snapshotID = identity
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MathAnalysis.analyze(source: source, document: document, sourceIdentity: snapshotID,
                                               maximumSpanCount: 256)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

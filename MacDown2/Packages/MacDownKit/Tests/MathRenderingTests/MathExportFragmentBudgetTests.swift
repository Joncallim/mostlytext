import Foundation
import Math
@testable import MathRendering
import Testing

@Suite("Math output admission before base64 and escaped allocation")
struct MathExportFragmentBudgetTests {
    private func image(bytes: Int = 4) -> RenderedMathImage {
        .init(pngData: Data(repeating: 0xFE, count: bytes), logicalWidth: 20, logicalHeight: 12)
    }

    @Test func exactHTMLAndPNGBoundariesIncludeEveryEncodedByte() throws {
        for count in 1 ... 50 {
            let image = image(bytes: count)
            var measured = MathExportFragmentBuilder()
            let expected = try measured.image(image, alt: "x<&\"'😀")
            #expect(measured.budget.htmlBytes == expected.utf8.count)
            #expect(measured.budget.pngBytes == count)
            var exact = MathExportFragmentBuilder(budget: .init(
                maximumPNGBytes: count, maximumHTMLBytes: expected.utf8.count
            ))
            #expect(try exact.image(image, alt: "x<&\"'😀").utf8.elementsEqual(expected.utf8))
            var short = MathExportFragmentBuilder(budget: .init(
                maximumPNGBytes: count, maximumHTMLBytes: expected.utf8.count - 1
            ))
            #expect(throws: MathExportFragmentBudget.Exhausted.self) { try short.image(image, alt: "x<&\"'😀") }
            #expect(short.budget.pngBytes == 0 && short.budget.htmlBytes == 0)
        }
    }

    @Test func aggregatePNGRejectionLeavesSpaceForReadableFallback() throws {
        var builder = MathExportFragmentBuilder(budget: .init(maximumPNGBytes: 6, maximumHTMLBytes: 1024))
        _ = try builder.image(image(), alt: "x")
        let admittedHTML = builder.budget.htmlBytes
        #expect(throws: MathExportFragmentBudget.Exhausted.self) { try builder.image(image(), alt: "y") }
        #expect(builder.budget.htmlBytes == admittedHTML && builder.budget.pngBytes == 4)
        let fallback = try builder.literal(source: "$y$", range: 0 ..< 3)
        #expect(fallback.contains("$y$"))
        #expect(builder.budget.pngBytes == 4)
        #expect(builder.budget.htmlBytes == admittedHTML + fallback.utf8.count)
    }

    @Test func literalEscapingPreservesOriginalScalarsAndCannotCreateMarkupOrURLs() throws {
        let body = "$x<&\"'😀$"
        let source = "before \u{600}" + body + "\u{301} after"
        let range = (source as NSString).range(of: body, options: .literal)
        var builder = MathExportFragmentBuilder()
        let actual = try builder.literal(source: source, range: range.location ..< NSMaxRange(range))
        let expected = "<code class=\"math-source-fallback\" style=\"white-space:pre-wrap\">" +
            "$x&lt;&amp;&quot;&#39;😀$</code>"
        #expect(actual.utf8.elementsEqual(expected.utf8))
        #expect(builder.budget.htmlBytes == actual.utf8.count)
        let hostile = "<img src='https://example.com' onerror='bad()'>\r\n$x$"
        let escaped = try builder.literal(source: hostile, range: 0 ..< hostile.utf16.count)
        #expect(!escaped.contains("<img") && !escaped.contains("src='"))
        #expect(escaped.contains("&lt;img src=&#39;https://example.com&#39;"))
        #expect(escaped.contains("\r\n$x$"))
    }

    @Test func exactLiteralBudgetRejectsEscapingExpansionAndAggregateOverflow() throws {
        var measured = MathExportFragmentBuilder()
        let expected = try measured.literal(source: "<&", range: 0 ..< 2)
        var exact = MathExportFragmentBuilder(budget: .init(maximumPNGBytes: 0, maximumHTMLBytes: expected.utf8.count))
        #expect(try exact.literal(source: "<&", range: 0 ..< 2) == expected)
        let bytes = exact.budget.htmlBytes
        #expect(throws: MathExportFragmentBudget.Exhausted.self) { try exact.literal(source: "x", range: 0 ..< 1) }
        #expect(exact.budget.htmlBytes == bytes)
        var short = MathExportFragmentBuilder(budget: .init(
            maximumPNGBytes: 0,
            maximumHTMLBytes: expected.utf8.count - 1
        ))
        #expect(throws: MathExportFragmentBudget.Exhausted.self) { try short.literal(source: "<&", range: 0 ..< 2) }
        #expect(short.budget.htmlBytes == 0)
        var hostile = MathExportFragmentBudget(maximumPNGBytes: Int.max, maximumHTMLBytes: Int.max)
        try hostile.admit(png: Int.max, html: Int.max)
        #expect(throws: MathExportFragmentBudget.Exhausted.self) { try hostile.admit(png: 1, html: 1) }
        #expect(hostile.pngBytes == Int.max && hostile.htmlBytes == Int.max)
    }

    @Test func invalidSourceEndpointsAndRendererDimensionsNeverConsumeOutputAllowance() {
        var builder = MathExportFragmentBuilder()
        for range in [-1 ..< 1, 0 ..< 0, 0 ..< 1, 1 ..< 3, 0 ..< 20] {
            #expect(throws: MathRenderError.self) { try builder.literal(source: "😀\r\nx", range: range) }
        }
        #expect(throws: MathRenderError.self) { try builder.literal(source: "a\r\nb", range: 0 ..< 2) }
        for width in [Double.nan, .infinity, -1, 0, 0.1, Double(Int.max)] {
            let invalid = RenderedMathImage(pngData: Data([0]), logicalWidth: width, logicalHeight: 12)
            #expect(throws: MathRenderError.self) { try builder.image(invalid, alt: "x") }
        }
        #expect(builder.budget.pngBytes == 0 && builder.budget.htmlBytes == 0)
    }

    @Test func cancellationAbandonsBothEncodingPaths() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var builder = MathExportFragmentBuilder()
            #expect(throws: CancellationError.self) { try builder.literal(source: "$x$", range: 0 ..< 3) }
            #expect(throws: CancellationError.self) { try builder.image(image(), alt: "x") }
            #expect(builder.budget.htmlBytes == 0 && builder.budget.pngBytes == 0)
        }
        await task.value
    }
}

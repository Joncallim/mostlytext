import Contributions
import Foundation
import MarkdownEngine
@testable import Math
import Testing

@Suite("Math export failure diagnostics")
struct MathFailureDiagnosticTests {
    private static let context = ExportMathRenderContext(
        foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1, pixelScale: 3
    )

    private static func document() -> MarkdownDocument {
        MarkdownDocument(
            body: "", bodyLineOffset: 0, blocks: [], headings: [], frontMatter: nil,
            sourceMap: SourceMap(text: ""), revision: 0, options: .default
        )
    }

    private static func fakeImage(for latex: String) -> RenderedMathImage {
        RenderedMathImage(pngData: Data("PNG:\(latex)".utf8), logicalWidth: 10, logicalHeight: 10)
    }

    @Test func failurePreservesLiteralEquationAndHidesUnknownRendererDetails() async throws {
        struct PrivateRendererFailure: LocalizedError {
            var errorDescription: String? {
                "PRIVATE-RENDERER-DETAIL"
            }
        }
        let latex = "α + 🧑🏽‍💻 + %@ + %lld"
        let source = "$\(latex)$ then $good$"
        let contribution = MathContribution(context: Self.context) { span, _ in
            if span.latex == latex {
                throw PrivateRendererFailure()
            }
            return Self.fakeImage(for: span.latex)
        }
        let results = try await contribution.run(document: Self.document(), sourceText: source, sourceGeneration: 42)
        #expect(results.count == 2)
        let failure = try #require(results.first)
        #expect(failure.content == nil)
        #expect(failure.sourceGeneration == 42)
        let diagnostic = try #require(failure.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message.contains(latex))
        #expect(!diagnostic.message.contains("PRIVATE-RENDERER-DETAIL"))
        #expect(results[1].content != nil)
        #expect(results[1].diagnostics.isEmpty)
        #expect(source == "$\(latex)$ then $good$")
    }

    @Test func correctedSubsequentSourceRecoversWithoutRetainingFailure() async throws {
        let contribution = MathContribution(context: Self.context) { span, _ in
            if span.latex == "bad" {
                throw MathRenderError.couldNotTypeset
            }
            return Self.fakeImage(for: span.latex)
        }
        let failed = try await contribution.run(document: Self.document(), sourceText: "$bad$", sourceGeneration: 7)
        #expect(failed.first?.content == nil)
        #expect(failed.first?.diagnostics.count == 1)
        let corrected = try await contribution.run(document: Self.document(), sourceText: "$good$", sourceGeneration: 8)
        #expect(corrected.count == 1)
        #expect(corrected.first?.content?.sourceRange == 0 ..< 6)
        #expect(corrected.first?.sourceGeneration == 8)
        #expect(corrected.first?.diagnostics.isEmpty == true)
    }
}

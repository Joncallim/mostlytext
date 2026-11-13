import ExportService
import Foundation
import Testing

@Suite("Passive Quick Look derived composition")
struct PassiveQuickLookDerivedTests {
    @Test func oneStaleItemPreservesItsSourceBesideAcceptedStaticContent() {
        let source = "Before $x^2$ and $bad$ after.\n"
        let good = range(of: "$x^2$", in: source)
        let stale = range(of: "$bad$", in: source)
        let html = ExportService.renderPassiveMarkdownFragment(
            source,
            contributions: [
                .init(sourceRange: good, placement: .inline, html: "<strong>MATH_STATIC</strong>",
                      sourceGeneration: 7),
                .init(sourceRange: stale, placement: .inline, html: "<strong>STALE_STATIC</strong>",
                      sourceGeneration: 6),
            ],
            sourceGeneration: 7
        )
        #expect(html.contains("<strong>MATH_STATIC</strong>"))
        #expect(html.contains("$bad$"))
        #expect(!html.contains("STALE_STATIC"))
        #expect(!html.contains("E12INLINE"))
    }

    @Test func invalidRangeCannotReplaceAnotherItemOrExposeAuthoredURLs() {
        let source = "[open](https://example.invalid/path) and $x^2$.\n"
        let good = range(of: "$x^2$", in: source)
        let html = ExportService.renderPassiveMarkdownFragment(
            source,
            contributions: [
                .init(sourceRange: 999 ..< 1000, placement: .inline,
                      html: "<strong>OUTSIDE</strong>", sourceGeneration: 1),
                .init(sourceRange: good, placement: .inline,
                      html: "<strong>MATH_STATIC</strong>", sourceGeneration: 1),
            ],
            sourceGeneration: 1
        )
        #expect(html.contains("<strong>MATH_STATIC</strong>"))
        #expect(!html.contains("OUTSIDE"))
        #expect(!html.contains("example.invalid"))
        #expect(html.contains("open"))
    }

    @Test func generatedMarkupCannotNavigateOrFetchExternalResources() {
        let source = "$x^2$\n"
        let html = ExportService.renderPassiveMarkdownFragment(
            source,
            contributions: [
                .init(sourceRange: range(of: "$x^2$", in: source), placement: .inline,
                      html: "<a href=\"https://example.invalid/go\">math</a>"
                          + "<img src=\"https://example.invalid/pixel\" "
                          + "srcset=\"https://example.invalid/large 2x\" />"
                          + "<video poster=\"https://example.invalid/poster\"></video>"
                          + "<table background=\"https://example.invalid/pattern\"></table>"
                          + "<p data=\"https://example.invalid/object\"></p>"
                          + "<script>alert(1)</script>",
                      sourceGeneration: 1),
            ],
            sourceGeneration: 1
        )
        #expect(html.contains("math"))
        #expect(!html.contains("example.invalid"))
        #expect(!html.contains("srcset="))
        #expect(!html.contains("poster="))
        #expect(!html.contains("background="))
        #expect(!html.contains(" data="))
        #expect(!html.contains("<script"))
    }

    @Test func oversizedItemPreservesOnlyItsOwnSource() {
        let source = "$large$ and $small$\n"
        let html = ExportService.renderPassiveMarkdownFragment(
            source,
            contributions: [
                .init(sourceRange: range(of: "$large$", in: source), placement: .inline,
                      html: String(repeating: "x", count: (1 << 20) + 1), sourceGeneration: 1),
                .init(sourceRange: range(of: "$small$", in: source), placement: .inline,
                      html: "<strong>SMALL_STATIC</strong>", sourceGeneration: 1),
            ],
            sourceGeneration: 1
        )
        #expect(html.contains("$large$"))
        #expect(html.contains("<strong>SMALL_STATIC</strong>"))
        #expect(html.utf8.count < 4096)
    }

    private func range(of needle: String, in source: String) -> Range<Int> {
        let match = (source as NSString).range(of: needle)
        return match.location ..< (match.location + match.length)
    }
}

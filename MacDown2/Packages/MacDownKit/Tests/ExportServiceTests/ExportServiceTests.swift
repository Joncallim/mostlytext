@testable import ExportService
import Testing

@Test func moduleLoads() {
    #expect(ExportService.moduleName == "ExportService")
}

@Suite("renderMarkdownFragment")
struct RenderMarkdownFragmentTests {
    @Test func passiveQuickLookFragmentUsesGFMWithoutAuthoredURLsOrActiveHTML() {
        let markdown = """
        | Column | Value |
        | --- | --- |
        | one | ~~two~~ |

        [link](https://example.invalid/path) ![picture](https://example.invalid/image.png)
        <script>alert(1)</script>
        """
        let html = ExportService.renderPassiveMarkdownFragment(markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<del>two</del>"))
        #expect(html.contains("link"))
        #expect(html.contains("picture"))
        #expect(!html.contains("example.invalid"))
        #expect(!html.contains("<script>"))
    }

    @Test func rendersAMarkdownListToHTML() {
        let html = ExportService.renderMarkdownFragment("- One\n- Two")
        #expect(html.contains("<li>One</li>"))
        #expect(html.contains("<li>Two</li>"))
    }

    /// Contribution-generated fragments are more conservative than the main
    /// document pipeline (epic-14-implementation.md §6.4, §10): no raw HTML
    /// passthrough, regardless of how cmark-gfm itself represents that
    /// (escaped text or an omission comment — either way the literal tag
    /// never appears live in the output).
    @Test func doesNotPreserveRawHTML() {
        let html = ExportService.renderMarkdownFragment("<script>alert(1)</script>")
        #expect(!html.contains("<script>"))
    }

    @Test func rendersEmptyInputAsEmptyOutput() {
        #expect(ExportService.renderMarkdownFragment("").isEmpty)
    }
}

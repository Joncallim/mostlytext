import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes

/// The fixed document-title policy (issue #49 / architecture Phase 2):
/// front-matter title vs. filename fallback vs. an authored opening heading,
/// kept in its own file so `ExportComposerTests` stays under the type-body
/// length SwiftLint enforces.
struct ExportTitleTests {
    @Test func frontMatterTitleLandsInDocumentMetadata() async throws {
        let markdown = """
        ---
        title: My Title
        ---
        # Hello
        """
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.title == "My Title")

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("<title>My Title</title>"))
        #expect(html.contains("<h1>Hello</h1>"))
        // The document already opens with its own heading; the front-matter
        // title must not add a second, different one above it.
        #expect(!html.contains("<h1>My Title</h1>"))
    }

    @Test func frontMatterTitleDoesNotDuplicateAnAuthoredOpeningHeading() async throws {
        // A document that already opens with `# Report Q3` has written its
        // title as visible content; front matter still supplies the browser
        // `<title>`, but must not inject a second, redundant `<h1>`.
        let markdown = "---\ntitle: Report Q3\n---\n# Report Q3\n\nBody text.\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 17, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.title == "Report Q3")
        #expect(prepared.visibleTitle == nil)

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("<title>Report Q3</title>"))
        #expect(html.contains("<h1>Report Q3</h1>"))
        // Exactly one <h1>: the authored one, not a synthesised duplicate.
        #expect(html.components(separatedBy: "<h1>").count == 2)
    }

    @Test func frontMatterTitleStillSynthesisesAHeadingWhenTheBodyOpensWithSomethingElse() async throws {
        // A leading paragraph, list or non-H1 heading is not the document's
        // title in visible form, so front matter must still supply one.
        let markdown = "---\ntitle: Report Q3\n---\n## Subsection\n\nBody text.\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 18, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.visibleTitle == "Report Q3")

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("<h1>Report Q3</h1>"))
        #expect(html.contains("<h2>Subsection</h2>"))
    }

    @Test func frontMatterTitleAlsoBecomesAVisibleHeading() async throws {
        let markdown = "---\ntitle: Quarterly Report\n---\nBody text.\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 12, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.title == "Quarterly Report")
        #expect(prepared.visibleTitle == "Quarterly Report")

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("<title>Quarterly Report</title>"))
        #expect(html.contains("<h1>Quarterly Report</h1>"))
    }

    @Test func aSavedDocumentWithoutFrontMatterTitlesFromItsFilename() async throws {
        // Otherwise the browser tab shows a file path, which is the common case:
        // most documents carry no front matter at all.
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: "# Hello\n",
                sourceGeneration: 13,
                theme: ExportTestSupport.lightTheme(),
                documentURL: URL(fileURLWithPath: "/tmp/notes/Meeting Notes.md")
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.title == "Meeting Notes")
        // A filename is not a heading the author wrote, so it never becomes one.
        #expect(prepared.visibleTitle == nil)

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("<title>Meeting Notes</title>"))
        #expect(!html.contains("<h1>Meeting Notes</h1>"))
    }

    @Test func anUntitledDocumentWithoutFrontMatterHasNoBrowserTitle() async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hello\n", sourceGeneration: 14, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.title.isEmpty)
        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(!html.contains("<title>"))
    }

    @Test func aNonScalarFrontMatterTitleWarnsAndIsNotUsed() async throws {
        let markdown = "---\ntitle:\n  - one\n  - two\n---\nBody.\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 15,
                theme: ExportTestSupport.lightTheme(),
                documentURL: URL(fileURLWithPath: "/tmp/notes/fallback.md")
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.title == "fallback")
        #expect(prepared.visibleTitle == nil)
        #expect(prepared.diagnostics.contains { $0.severity == .warning && $0.message.contains("title") })
    }

    @Test func htmlTitlesAreEscaped() async throws {
        let markdown = "---\ntitle: \"A <b>bold</b> & risky title\"\n---\nBody.\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 16, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(!html.contains("<b>bold</b>"))
        #expect(html.contains("&lt;b&gt;bold&lt;/b&gt;"))
        #expect(html.contains("&amp;"))
    }
}

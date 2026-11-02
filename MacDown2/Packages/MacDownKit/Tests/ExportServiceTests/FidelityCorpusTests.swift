import ExportService
import Foundation
import Testing

/// Slice 6 (fidelity): a representative corpus of ordinary Markdown whose
/// exported HTML is reviewed for intentional, stable properties rather than
/// assumed to match an arbitrary renderer. Each entry asserts the structure
/// that must survive export and the constructs that must not leak through.
struct FidelityCorpusTests {
    struct CorpusEntry {
        let name: String
        let markdown: String
        let expected: [String]
        let forbidden: [String]
    }

    private let corpus: [CorpusEntry] = [
        .init(
            name: "headings",
            markdown: "# One\n\n## Two\n\n###### Six\n",
            expected: ["<h1>One</h1>", "<h2>Two</h2>", "<h6>Six</h6>"],
            forbidden: []
        ),
        .init(
            name: "paragraphsAndEmphasis",
            markdown: "plain **bold** and *italic* and `code`.\n",
            expected: ["<strong>bold</strong>", "<em>italic</em>", "<code>code</code>"],
            forbidden: []
        ),
        .init(
            name: "lists",
            markdown: "- one\n- two\n\n1. first\n2. second\n",
            expected: ["<ul>", "<li>one</li>", "<li>two</li>", "<ol>", "<li>first</li>"],
            forbidden: []
        ),
        .init(
            name: "blockquote",
            markdown: "> quoted text\n>\n> more\n",
            expected: ["<blockquote>", "quoted text"],
            forbidden: []
        ),
        .init(
            name: "fencedCodeBlock",
            markdown: "```swift\nlet x = 1\n```\n",
            expected: ["<pre>", "<code class=\"language-swift\">", "let x = 1"],
            forbidden: []
        ),
        .init(
            name: "table",
            markdown: "| h1 | h2 |\n| -- | -- |\n| a  | b  |\n",
            expected: ["<table>", "<th>h1</th>", "<td>b</td>"],
            forbidden: []
        ),
        .init(
            name: "thematicBreak",
            markdown: "before\n\n---\n\nafter\n",
            expected: ["<hr", "before", "after"],
            forbidden: []
        ),
        .init(
            name: "link",
            markdown: "[example](https://example.com \"title\")\n",
            expected: ["<a href=\"https://example.com\" title=\"title\">example</a>"],
            forbidden: []
        ),
        .init(
            name: "autolink",
            markdown: "visit <https://example.com> now\n",
            expected: ["<a href=\"https://example.com\">https://example.com</a>"],
            forbidden: []
        ),
        .init(
            name: "frontMatter",
            markdown: "---\ntitle: Corpus Doc\nauthor: Me\n---\n# Body\n",
            expected: ["<title>Corpus Doc</title>", "<h1>Body</h1>"],
            forbidden: ["author: Me", "---"]
        ),
    ]

    @Test(arguments: [
        "headings", "paragraphsAndEmphasis", "lists", "blockquote", "fencedCodeBlock",
        "table", "thematicBreak", "link", "autolink", "frontMatter",
    ])
    func corpusEntryRendersAsReviewed(name: String) async throws {
        let entry = try #require(corpus.first { $0.name == name })
        let prepared = try await ExportService.prepare(
            ExportRequest(text: entry.markdown, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/corpus.html"), mode: .standalone(style: .embedded))
        )
        let html = try ExportHTMLWriter.companionHTML(from: prepared, style: .embedded)

        for expected in entry.expected {
            #expect(html.contains(expected), "\(name): missing \(expected)")
        }
        for forbidden in entry.forbidden {
            #expect(!html.contains(forbidden), "\(name): unexpectedly present \(forbidden)")
        }
    }

    @Test func remoteImageIsNeverFetchedForSelfContained() async throws {
        let markdown = "# Img\n\n![alt](https://example.com/x.png)\n"
        await #expect(throws: ExportError.self) {
            _ = try await ExportService.prepare(
                ExportRequest(text: markdown, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
                target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
            )
        }
    }

    @Test func selfContainedDocumentIsFullyEmbedded() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "img.png", in: directory, bytes: Data([0x89, 0x50]))

        let markdown = "# Img\n\n![alt](img.png)\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 2,
                theme: ExportTestSupport.lightTheme(),
                documentURL: directory.appendingPathComponent("doc.md"),
                resourceAccess: ExportResourceAccess(openingDirectory: directory)
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        // No `<name>.assets/…` companion reference of any kind should survive
        // self-contained embedding, whatever the per-document directory name.
        #expect(!html.contains(".assets/"))
        #expect(html.contains("data:image/png;base64,"))
    }
}

import Foundation
@testable import MarkdownEngine
import Testing

@Suite("Front matter line-ending fidelity")
struct FrontMatterLineEndingTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func parsesMetadataAndKeepsExactOriginalBody(ending: String) async throws {
        for closer in ["---", "..."] {
            let header = "\u{FEFF}---\(ending)title: café\(ending)count: 42\(ending)\(closer)\(ending)"
            let body = "# 🙂 Body\(ending)tail\r\n"
            let document = try await ParseEngine().parse(header + body, revision: 4)
            let metadata = try #require(document.frontMatter)
            #expect(metadata.raw == "title: café\ncount: 42")
            #expect(metadata.values?["title"] == .string("café"))
            #expect(metadata.values?["count"] == .int(42))
            #expect(metadata.lineRange == 1 ... 4)
            #expect(document.bodyLineOffset == 4)
            #expect(document.body == body)
            #expect(document.blocks.first?.lineRange == 5 ... 5)
            let range = document.sourceMap.utf16Range(ofLines: 5 ... 6)
            #expect(range.location == header.utf16.count)
            #expect(((header + body) as NSString).substring(with: range) == "# 🙂 Body\(ending)tail")
        }
    }

    @Test func mixedHeaderEndingsAndNoFinalBodyEnding() async throws {
        let source = "---\rtitle: Hello\r\ncount: 42\n---\r# Body"
        let document = try await ParseEngine().parse(source, revision: 0)
        #expect(document.bodyLineOffset == 4)
        #expect(document.frontMatter?.raw == "title: Hello\ncount: 42")
        #expect(document.body == "# Body")
        #expect(document.blocks.first?.lineRange == 5 ... 5)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func emptyMetadataAndClosingAtEndOfInput(ending: String) async throws {
        let source = "---\(ending)---"
        let document = try await ParseEngine().parse(source, revision: 0)
        #expect(document.frontMatter?.raw == "")
        #expect(document.bodyLineOffset == 2)
        #expect(document.body == "")
        #expect(document.blocks.isEmpty)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func thematicBreakAndUnterminatedHeaderStayInBody(ending: String) async throws {
        for source in ["---\(ending)\(ending)text\(ending)---", "---\(ending)title: Hello"] {
            let document = try await ParseEngine().parse(source, revision: 0)
            #expect(document.frontMatter == nil)
            #expect(document.bodyLineOffset == 0)
            #expect(document.body == source)
        }
    }

    @Test func lineRecordsAgreeWithOriginalSourceCoordinates() {
        for source in ["", "\n", "\r\n", "\r", "🙂\r\na\rb\n", "a\n\rb", "a\r\r\nb"] {
            let lines = source.lines()
            let map = SourceMap(text: source)
            #expect(lines.map(\.startOffset) == map.lineStartOffsets)
            #expect(lines.map(\.lineNumber) == Array(1 ... map.lineCount))
            #expect(lines.map(\.endOffset) == Array(map.lineStartOffsets.dropFirst()) + [source.utf16.count])
            #expect(lines.allSatisfy { !$0.text.contains("\r") && !$0.text.contains("\n") })
        }
    }
}

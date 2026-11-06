import Foundation
import Highlighting
import SwiftTreeSitter
import Testing

@MainActor
@Suite("Immutable query capture values", .serialized)
struct ImmutableQueryCaptureValueTests {
    @Test func captureNamesRetainNamedAndGlobalDirectiveSemantics() throws {
        let language = try markdownLanguage()
        let query = try Query(language: language, data: Data("""
        ((atx_heading (atx_h1_marker) @punctuation.heading) @heading.text
          (#set! @heading.text role "first")
          (#set! @heading.text role "last")
          (#set! @punctuation.heading role "marker")
          (#set! global "match"))
        """.utf8))
        let tree = try parse("# First e\u{301} 😀\n\nBody.\n\n# Last\n", using: language)
        let matches = Array(query.execute(in: tree, depth: 3))
        try #require(matches.count == 2)
        for match in matches {
            #expect(match.metadata == ["global": "match"])
            try #require(match.captures.count == 2)
            for capture in match.captures {
                #expect(capture.depth == 3)
                #expect(capture.name == query.captureName(for: capture.index))
                if capture.nameComponents == ["heading", "text"] {
                    #expect(capture.metadata == ["role": "last"])
                } else {
                    #expect(capture.nameComponents == ["punctuation", "heading"])
                    #expect(capture.metadata == ["role": "marker"])
                }
            }
        }
    }

    @Test func oneQueryKeepsCurrentTreeRangesWhenSourceOffsetsChange() throws {
        let language = try markdownLanguage()
        let query = try Query(language: language, data: Data("(atx_h1_marker) @punctuation.heading.marker".utf8))
        for prefix in ["body", "😀 e\u{301}", "first\r\nsecond\r\n"] {
            let beforeHeading = prefix + "\r\n\r\n"
            let tree = try parse(beforeHeading + "# Heading\r\n", using: language)
            let captures = query.execute(in: tree).flatMap(\.captures)
            try #require(captures.count == 1)
            #expect(captures[0].range == NSRange(location: beforeHeading.utf16.count, length: 1))
            #expect(captures[0].nameComponents == ["punctuation", "heading", "marker"])
        }
    }

    @Test func independentCursorsShareAnImmutableQueryConcurrently() async throws {
        let language = try markdownLanguage()
        let query = try Query(language: language, data: Data("(atx_h1_marker) @punctuation.heading.marker".utf8))
        let tree = try parse(String(repeating: "# One 😀\n\nBody.\n\n", count: 64), using: language)
        let expected = query.execute(in: tree, depth: 2).highlights()
        try #require(expected.count == 64)
        await withTaskGroup(of: [NamedRange].self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    query.execute(in: tree, depth: 2).highlights()
                }
            }
            for await observed in group {
                #expect(observed == expected)
            }
        }
    }

    private func markdownLanguage() throws -> Language {
        try #require(GrammarRegistry().configuration(for: "markdown")).language
    }

    private func parse(_ source: String, using language: Language) throws -> Tree {
        let parser = Parser()
        try parser.setLanguage(language)
        let mutable = try #require(parser.parse(source))
        return try #require(mutable.copy())
    }
}

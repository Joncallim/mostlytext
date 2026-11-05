import Foundation
@testable import MarkdownEngine
import Testing

struct MarkdownReferenceRepairTests {
    private struct Replacement {
        let range: Range<Int>
        let text: String
    }

    private func apply(_ edits: [Replacement], to source: String) -> String {
        let text = NSMutableString(string: source)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            text.replaceCharacters(
                in: NSRange(location: edit.range.lowerBound, length: edit.range.count),
                with: edit.text
            )
        }
        return text as String
    }

    private func replacements(_ source: String, facts: MarkdownSourceFacts) -> [Replacement] {
        let text = source as NSString
        return facts.links.flatMap { link -> [Replacement] in
            guard let label = link.labelRange else { return [] }
            return ["$x$", "$y$"].compactMap { expression in
                let range = text.range(of: expression, options: .literal,
                                       range: NSRange(location: label.lowerBound, length: label.count))
                guard range.location != NSNotFound else { return nil }
                return Replacement(range: range.location ..< NSMaxRange(range), text: "MTREFERENCEPLACEHOLDER")
            }
        }
    }

    private func verify(_ source: String, expectedLinks: Int = 1) async throws {
        let engine = ParseEngine()
        let original = try await engine.parse(source, revision: 1)
        let facts = try #require(original.sourceFacts)
        #expect(facts.links.count == expectedLinks)
        let replacements = replacements(source, facts: facts)
        #expect(!replacements.isEmpty)
        let repairs = try MarkdownReferenceRepair.edits(
            source: source,
            facts: facts,
            replacing: replacements.map(\.range)
        )
        let rewritten = apply(replacements + repairs.map { Replacement(range: $0.sourceRange, text: $0.replacement) },
                              to: source)
        let reparsed = try await engine.parse(rewritten, revision: 2)
        let links = try #require(reparsed.sourceFacts).links
        #expect(links.count == facts.links.count, "Original: \(source); rewritten: \(rewritten)")
        #expect(links.map { $0.destination.map { Data($0.utf8) } } == facts.links
            .map { $0.destination.map { Data($0.utf8) } })
        #expect(links.map { $0.title.map { Data($0.utf8) } } == facts.links.map { $0.title.map { Data($0.utf8) } })
        let expectedTitles = original.headings.map {
            $0.title.replacingOccurrences(of: "$x$", with: "MTREFERENCEPLACEHOLDER", options: .literal)
                .replacingOccurrences(of: "$y$", with: "MTREFERENCEPLACEHOLDER", options: .literal)
        }
        #expect(reparsed.headings.map { Data($0.title.utf8) } == expectedTitles.map { Data($0.utf8) })
    }

    @Test func realParserShowsTheUnrepairedReferenceLossAndTheRestoredTarget() async throws {
        let source = "[$x$][]\n\n[$x$]: /target \"title\""
        let original = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(original.sourceFacts)
        let replacements = replacements(source, facts: facts)
        let broken = try await ParseEngine().parse(apply(replacements, to: source), revision: 2)
        #expect(facts.links.map(\.destination) == ["/target"])
        #expect(try #require(broken.sourceFacts).links.isEmpty)
        try await verify(source)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func shortcutCollapsedExplicitEscapedAndMultilineDefinitionsPreserveTargets(ending: String) async throws {
        for (label, suffix, definition) in [
            ("$x$", "", "[$x$]: /target \"title\""),
            ("$x$", "[]", "[$x$]: /target 'title'"),
            ("$x$", "[key]", "[key]: /target (title)"),
            ("$x$ \\[term\\]", "[]", "[$x$ \\[term\\]]: /target \"title\""),
            ("$x$", "[]", "[$x$]:" + ending + "  /target" + ending + "  \"multiline title\""),
            ("$x$", "[]", "[$x$]: /target \"title" + ending + "  continued\""),
        ] {
            try await verify("[" + label + "]" + suffix + ending + ending + definition)
        }
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func nestedQuoteListAndLazyContinuationKeysKeepTheirActualIdentity(ending: String) async throws {
        for continuation in [">   rest", "rest"] {
            let source = "> - [prefix $x$" + ending + continuation + "][]" + ending + ending +
                "[prefix $x$ rest]: /target \"title\""
            try await verify(source)
        }
    }

    @Test(arguments: ["\u{301}", "\u{600}", "\u{FE0F}", "\u{200C}", "😀漢"])
    func scalarAdjacencyDoesNotChangeReferenceIdentity(scalar: String) async throws {
        let label = scalar + "$x$" + scalar
        try await verify("[" + label + "][]" + scalar + "\n\n[" + label + "]: /target \"title\"")
    }

    @Test func multipleReplacementsRepairEachLinkOnlyOnceAndRespectRealDefinitions() async throws {
        let source = "[$x$ and $y$][] then [$x$]\n\n```md\n[$x$]: /wrong\n```\n\n" +
            "[$x$ and $y$]: /first \"one\"\n[$x$]: /second \"two\""
        try await verify(source, expectedLinks: 2)
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let edits = try MarkdownReferenceRepair.edits(source: source, facts: facts,
                                                      replacing: replacements(source, facts: facts).map(\.range))
        #expect(edits.count == 2)
        #expect(edits.allSatisfy { !$0.sourceRange.isEmpty })
        #expect(facts.links.map(\.destination) == ["/first", "/second"])
    }

    @Test func fullKeysInlineTargetsAndUnrelatedLinksNeedNoRepair() async throws {
        let source = "[$x$][key] then [$y$](/inline) then [unchanged][]\n\n[key]: /target\n[unchanged]: /other"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        #expect(try MarkdownReferenceRepair.edits(source: source, facts: facts,
                                                  replacing: replacements(source, facts: facts).map(\.range)).isEmpty)
        #expect(try MarkdownReferenceRepair.edits(source: source, facts: facts, replacing: []).isEmpty)
    }

    @Test func canonicalLookalikeKeysKeepByteDistinctDestinationsAndTitlesSeparate() async throws {
        let first = "$x$é", second = "$x$e\u{301}"
        let source = "[" + first + "][] and [" + second + "][]\n\n[" + first +
            "]: /é \"é\"\n[" + second + "]: /e\u{301} \"e\u{301}\""
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        #expect(facts.links.map { $0.destination.map { Data($0.utf8) } } == [Data("/é".utf8), Data("/e\u{301}".utf8)])
        #expect(facts.links.map { $0.title.map { Data($0.utf8) } } == [Data("é".utf8), Data("e\u{301}".utf8)])
        try await verify(source, expectedLinks: 2)
    }

    @Test func tableReferencesKeepTheirOwnCellEscapesAndRawImplicitKey() async throws {
        for (label, key) in [("$x$", "$x$"), ("$x$`tail", "$x$`tail"), ("$x$\\|pipe", "$x$|pipe")] {
            let source = "| A | B |\n|---|---|\n| [" + label + "][] | other |\n\n[" + key + "]: /target \"title\""
            try await verify(source)
        }
    }

    @Test func overlappingOrDuplicateReplacementAuthorityIsRejected() async throws {
        let source = "[$x$][]\n\n[$x$]: /target"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let range = try #require(replacements(source, facts: facts).first).range
        for ranges in [[range, range], [range, (range.lowerBound + 1) ..< range.upperBound]] {
            #expect(throws: MarkdownReferenceRepair.Failure.invalidRange) {
                try MarkdownReferenceRepair.edits(source: source, facts: facts, replacing: ranges)
            }
        }
    }

    @Test func punctuationKeysRetainOnlyTheirOriginalResolvedTargetAndTitle() async throws {
        var accepted = 0
        for value in UInt32(33) ... 126 {
            let scalar = try #require(Unicode.Scalar(value))
            let character = String(scalar)
            let escaped = ["[", "]", "\\"].contains(character) ? "\\" + character : character
            let label = "$x$" + escaped + "tail"
            let source = "[" + label + "][]\n\n[" + label + "]: /target \"title\""
            let original = try await ParseEngine().parse(source, revision: 1)
            let facts = try #require(original.sourceFacts)
            guard facts.links.count == 1 else { continue } // Only the actual parser can authorize a reference.
            accepted += 1
            try await verify(source)
        }
        #expect(accepted >= 60, "The corpus must exercise many real references, not silently skip every case")
    }

    @Test(arguments: [
        "$x$`tail", "$x$``tail", "$x$\\`tail", "$x$\\\\`tail", "$x$ `code` and `tail",
        "$x$ \\`quoted\\` and `tail", "$x$ <span title='`'>$y$</span> and `tail",
    ])
    func unmatchedLiteralDelimitersCannotBecomeCodeSpansAcrossTheReferenceKey(label: String) async throws {
        try await verify("# [" + label + "][]\n\n[" + label + "]: /target \"title\"")
    }

    @Test func canonicalLookalikeSourceAndNonScalarRangesCannotBorrowAuthority() async throws {
        let source = "e\u{301} 😀 [$x$][]\r\n\r\n[$x$]: /target"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let lookalike = "é 😀 [$x$][]\r\n\r\n[$x$]: /target"
        #expect(source == lookalike)
        #expect(throws: MarkdownReferenceRepair.Failure.sourceMismatch) {
            try MarkdownReferenceRepair.edits(source: lookalike, facts: facts, replacing: [])
        }
        let emoji = (source as NSString).range(of: "😀", options: .literal)
        let crlf = (source as NSString).range(of: "\r\n", options: .literal)
        for range in [(emoji.location + 1) ..< NSMaxRange(emoji), crlf.location ..< (crlf.location + 1), -1 ..< 1] {
            #expect(throws: MarkdownReferenceRepair.Failure.invalidRange) {
                try MarkdownReferenceRepair.edits(source: source, facts: facts, replacing: [range])
            }
        }
    }
}

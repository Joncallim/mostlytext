import Foundation
import MarkdownEngine
@testable import Preview
import Testing
import Textual

@MainActor
@Suite("Native replay of original parser reference scope", .serialized)
struct PreviewReferenceReplayTests {
    private func range(_ text: String, in source: String) throws -> Range<Int> {
        let found = (source as NSString).range(of: text, options: .literal)
        try #require(found.location != NSNotFound)
        return found.location ..< NSMaxRange(found)
    }

    private struct Prepared {
        let input: PreviewMathInput
        let id: UUID
        let facts: MarkdownSourceFacts
    }

    private func input(source: String, block: String) async throws -> Prepared {
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let blockRange = try range(block, in: source)
        let localMath = try range("$x$", in: block)
        let globalMath = (localMath.lowerBound + blockRange.lowerBound) ..<
            (localMath.upperBound + blockRange.lowerBound)
        let repairs = try MarkdownReferenceRepair.edits(source: source, facts: facts, replacing: [globalMath])
        let edits = repairs.map { edit in
            PreviewMathInput.SourceEdit(
                range: (edit.sourceRange.lowerBound - blockRange.lowerBound) ..<
                    (edit.sourceRange.upperBound - blockRange.lowerBound),
                expectedSource: (source as NSString).substring(with: .init(
                    location: edit.sourceRange.lowerBound, length: edit.sourceRange.count
                )), replacement: edit.replacement
            )
        }
        let prefix = try MarkdownReferenceReplayIndex(facts: facts).prefix(
            for: blockRange, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: PreviewParserBudget.maximumUTF8Bytes
        )
        let id = UUID()
        let references = facts.links.filter { $0.fullRange.lowerBound >= blockRange.lowerBound }
            .compactMap { link -> PreviewMathInput.Reference? in
                guard link.fullRange.upperBound <= blockRange.upperBound,
                      let destination = link.destination else { return nil }
                return .init(
                    range: (link.fullRange.lowerBound - blockRange.lowerBound) ..<
                        (link.fullRange.upperBound - blockRange.lowerBound),
                    destination: destination,
                    kind: .link
                )
            }
        return try Prepared(input: PreviewMathInput(source: block, prefix: prefix, replacements: [
            .init(id: id, range: localMath, expectedSource: "$x$"),
        ], sourceEdits: edits, references: references), id: id, facts: facts)
    }

    private func render(_ input: PreviewMathInput, id: UUID) throws -> AttributedString {
        let attachment = AnyAttachment.math(latex: "x", style: .inline, sourceID: id)
            .withAccessibility(.init(label: "MT_REFERENCE_MATH_" + id.uuidString))
        return try PreviewMathMarkupParser(input: input, attachments: [id: attachment])
            .attributedString(for: input.source)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func consumedDefinitionsKeepActualNativeTargetsAndEquationAttributes(_ ending: String) async throws {
        let cases = [
            ("single line", "[key]: /right \"title\"\n\n[$x$][key]", "[$x$][key]"),
            ("fenced fake", "```\n[key]: /wrong \"fake\"\n```\n\n[key]: /right \"title\"\n\n[$x$][key]", "[$x$][key]"),
            ("multiline", "[key]:\n  /right\n  \"title\"\n\n[$x$][key]", "[$x$][key]"),
            ("escaped bracket", "[a\\]b]: /right \"title\"\n\n[$x$][a\\]b]", "[$x$][a\\]b]"),
            ("quote", "> [key]: /right\n> \"title\"\n\n[$x$][key]", "[$x$][key]"),
            ("list quote and implicit key", "> - [$x$]: /right\n>   \"title\"\n\n[$x$][]", "[$x$][]"),
        ]
        for (name, raw, block) in cases {
            let source = raw.replacingOccurrences(of: "\n", with: ending)
            let prepared = try await input(source: source, block: block)
            let input = prepared.input, id = prepared.id, facts = prepared.facts
            #expect(facts.links.map(\.destination) == ["/right"], "Original target: \(name)")
            #expect(facts.links.map(\.title) == ["title"], "Original title: \(name)")
            let actual = try render(input, id: id)
            let own = try #require(
                actual.runs.first { $0[PreviewMathSourceAttribute.self] == id },
                "Own attachment: \(name)"
            )
            #expect(own.link?.relativeString == "/right", "Native target: \(name)")
            #expect(own.textual.attachment?.accessibility?.label == "MT_REFERENCE_MATH_" + id.uuidString)
            let replay = try await ParseEngine().parse(input.rewritten, revision: 2)
            #expect(replay.sourceFacts?.links.map(\.title) == ["title"], "Actual replay title: \(name)")
        }
    }

    @Test func replayCannotMakeAnOriginallyExpansionLimitedEquationClickable() async throws {
        let target = "/" + String(repeating: "q", count: 8000)
        let block = "[seen][key] [$x$][key]"
        let source = "[key]: " + target + "\n\n" + Array(repeating: "[old][key]", count: 11)
            .joined(separator: " ") + "\n\n" + block
        let prepared = try await input(source: source, block: block)
        let input = prepared.input, id = prepared.id, facts = prepared.facts
        #expect(facts.links.count == 12)
        let originalMath = try range("$x$", in: source)
        #expect(!facts.links.contains { $0.fullRange.contains(originalMath.lowerBound) })
        let actual = try render(input, id: id)
        let own = actual.runs.first { $0[PreviewMathSourceAttribute.self] == id }
        #expect(own?.link == nil, "Replaying a definition must not create a link denied in the whole document")
        #expect(own != nil || String(String.UnicodeScalarView(actual.unicodeScalars)).utf8.elementsEqual(block.utf8))
        let positions = actual.runs.compactMap { run -> [Int]? in
            guard let position = run.markdownSourcePosition else { return nil }
            return [position.startLine, position.startColumn, position.endLine, position.endColumn]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "positions": positions,
            "mathGainedLink": own?.link != nil,
        ])
        try print("MOSTLYTEXT_REFERENCE_SCOPE " + #require(String(data: data, encoding: .utf8)))
    }

    @Test func nativeImagesKeepOnlyTheirOriginalResourceTargets() async throws {
        let source = "[image]: /picture.png \"title\"\n\n![alt][image]"
        let document = try await ParseEngine().parse(source, revision: 1)
        let facts = try #require(document.sourceFacts)
        let block = "![alt][image]"
        let blockRange = try range(block, in: source)
        let prefix = try MarkdownReferenceReplayIndex(facts: facts).prefix(
            for: blockRange, sourceSHA256: facts.sourceSHA256, maximumUTF8Bytes: PreviewParserBudget.maximumUTF8Bytes
        )
        let original = try #require(facts.images.first)
        let reference = try PreviewMathInput.Reference(range: 0 ..< block.utf16.count,
                                                       destination: #require(original.source), kind: .image)
        let input = try PreviewMathInput(source: block, prefix: prefix, replacements: [], references: [reference])
        let actual = try PreviewMathMarkupParser(input: input, attachments: [:]).attributedString(for: block)
        #expect(actual.runs.compactMap(\.imageURL).map(\.relativeString) == ["/picture.png"])
        let denied = try PreviewMathInput(source: block, prefix: prefix, replacements: [])
        let fallback = try PreviewMathMarkupParser(input: denied, attachments: [:]).attributedString(for: block)
        #expect(String(String.UnicodeScalarView(fallback.unicodeScalars)).utf8.elementsEqual(block.utf8))
        #expect(fallback.runs.allSatisfy { $0.imageURL == nil })
    }

    @Test func unrelatedAndWrongNativeLinkAttributesFailClosedWithoutAnyEquations() throws {
        let source = "[label](/actual)"
        let wrong = PreviewMathInput.Reference(range: 0 ..< source.utf16.count, destination: "/wrong", kind: .link)
        let foreignRole = PreviewMathInput.Reference(
            range: 0 ..< source.utf16.count,
            destination: "/actual",
            kind: .image
        )
        for references in [[], [wrong], [foreignRole]] {
            let input = try PreviewMathInput(source: source, replacements: [], references: references)
            let actual = try PreviewMathMarkupParser(input: input, attachments: [:]).attributedString(for: source)
            #expect(String(String.UnicodeScalarView(actual.unicodeScalars)).utf8.elementsEqual(source.utf8))
            #expect(actual.runs.allSatisfy { $0.link == nil && $0.imageURL == nil })
        }
        let reference = PreviewMathInput.Reference(range: 0 ..< source.utf16.count, destination: "/actual", kind: .link)
        let input = try PreviewMathInput(source: source, replacements: [], references: [reference])
        let base = try #require(URL(string: "https://example.com/document/"))
        let actual = try PreviewMathMarkupParser(input: input, attachments: [:], baseURL: base)
            .attributedString(for: source)
        #expect(actual.runs.compactMap(\.link).map(\.absoluteString) == ["https://example.com/actual"])
    }

    @Test func aMissingOriginalReferenceCannotRestoreAnEquationWithLostLinkAttributes() async throws {
        let block = "[$x$][key]"
        let source = "[key]: /right\n\n" + block
        let prepared = try await input(source: source, block: block)
        let positive = try render(prepared.input, id: prepared.id)
        #expect(positive.runs
            .contains { $0[PreviewMathSourceAttribute.self] == prepared.id && $0.link?.relativeString == "/right" })
        let original = try #require(prepared.facts.links.first)
        let destination = try #require(original.destination)
        // Deliberate lost-prefix fault: original authority still requires the
        // real link, but this native input cannot resolve its definition.
        let broken = try PreviewMathInput(source: block, replacements: [
            .init(id: prepared.id, range: 1 ..< 4, expectedSource: "$x$"),
        ], references: [.init(range: 0 ..< block.utf16.count, destination: destination, kind: .link)])
        let actual = try render(broken, id: prepared.id)
        #expect(String(String.UnicodeScalarView(actual.unicodeScalars)).utf8.elementsEqual(block.utf8))
        #expect(actual.runs.allSatisfy { $0.textual.attachment == nil && $0.link == nil })
    }
}

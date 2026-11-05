import Foundation
@testable import Preview
import Testing
import Textual

@MainActor
@Suite("Source-proven scalar-safe native math restoration", .serialized)
struct PreviewMathTransportTests {
    private let namespace = String(repeating: "B", count: 32)

    private func scalarText(_ value: some AttributedStringProtocol) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars))
    }

    private func replacement(in source: String, id: UUID = UUID()) throws -> PreviewMathInput.Replacement {
        let range = (source as NSString).range(of: "$x$", options: .literal)
        try #require(range.location != NSNotFound)
        return .init(id: id, range: range.location ..< NSMaxRange(range), expectedSource: "$x$")
    }

    private func attachment(_ id: UUID) -> AnyAttachment {
        .math(latex: "x", style: .inline, sourceID: id)
            .withAccessibility(.init(label: "MT_SCALAR_MATH_" + id.uuidString))
    }

    @Test(arguments: ["\u{600}", "\u{301}", "\u{FE0F}", "\u{200C}", "👩🏽‍💻", "漢"])
    func originalScalarNeighborsAndOwnAttachmentAttributesSurvive(_ neighbor: String) throws {
        let source = neighbor + "$x$" + neighbor
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, replacements: [occurrence], namespace: namespace)
        let parser = PreviewMathMarkupParser(input: input, attachments: [occurrence.id: attachment(occurrence.id)])
        let actual = try parser.attributedString(for: source)
        #expect(scalarText(actual).utf8.elementsEqual((neighbor + "\u{FFFC}" + neighbor).utf8))
        let ownRuns = actual.runs.filter { $0[PreviewMathSourceAttribute.self] == occurrence.id }
        try #require(ownRuns.count == 1)
        let run = try #require(ownRuns.first)
        #expect(scalarText(actual[run.range]).utf8.elementsEqual("\u{FFFC}".utf8))
        #expect(run.textual.attachment?.accessibility?.label == "MT_SCALAR_MATH_" + occurrence.id.uuidString)
        #expect(!scalarText(actual).contains(input.family))
    }

    @Test func noRendererKeepsAuthoredSourceInsideTheOriginalMarkdownAttributes() throws {
        let source = "**before $x$ after**"
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, replacements: [occurrence])
        let actual = try PreviewMathMarkupParser(input: input, attachments: [:]).attributedString(for: source)
        #expect(scalarText(actual).utf8.elementsEqual("before $x$ after".utf8))
        let own = try #require(actual.runs.first { $0[PreviewMathSourceAttribute.self] == occurrence.id })
        #expect(own.textual.attachment == nil)
        #expect(own.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(scalarText(actual[own.range]).utf8.elementsEqual("$x$".utf8))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func repairedImplicitKeysKeepActualReferenceTargetAttributes(_ ending: String) throws {
        let source = "[$x$][]"
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, prefix: "[$x$]: /target \"title\"" + ending + ending,
                                         replacements: [occurrence], sourceEdits: [
                                             .init(range: 4 ..< 7, expectedSource: "][]", replacement: "][$x$]"),
                                         ])
        let actual = try PreviewMathMarkupParser(input: input, attachments: [occurrence.id: attachment(occurrence.id)])
            .attributedString(for: source)
        let own = try #require(actual.runs.first { $0[PreviewMathSourceAttribute.self] == occurrence.id })
        #expect(own.link?.relativeString == "/target")
        #expect(own.textual.attachment != nil)
        #expect(scalarText(actual).utf8.elementsEqual("\u{FFFC}".utf8))
    }

    @Test func canonicalLookalikeReferenceKeysKeepTheirByteDistinctTargets() throws {
        let first = "é$x$"
        let second = "e\u{301}$x$"
        let source = "[" + first + "][] and [" + second + "][]"
        let literal = source as NSString
        let firstRange = literal.range(of: "$x$", options: .literal)
        let secondRange = literal.range(of: "$x$", options: .literal,
                                        range: NSRange(
                                            location: NSMaxRange(firstRange),
                                            length: literal.length - NSMaxRange(firstRange)
                                        ))
        let ids = [UUID(), UUID()]
        let replacements = [firstRange, secondRange].enumerated().map { index, range in
            PreviewMathInput.Replacement(
                id: ids[index],
                range: range.location ..< NSMaxRange(range),
                expectedSource: "$x$"
            )
        }
        let edits = zip([firstRange, secondRange], [first, second]).map { range, key in
            PreviewMathInput.SourceEdit(range: NSMaxRange(range) ..< (NSMaxRange(range) + 3),
                                        expectedSource: "][]", replacement: "][" + key + "]")
        }
        let prefix = "[" + first + "]: /caf%C3%A9\n[" + second + "]: /cafe%CC%81\n\n"
        let input = try PreviewMathInput(source: source, prefix: prefix, replacements: replacements, sourceEdits: edits)
        let actual = try PreviewMathMarkupParser(
            input: input,
            attachments: Dictionary(uniqueKeysWithValues: ids.map { ($0, attachment($0)) })
        )
        .attributedString(for: source)
        let targets = try ids.map { id in
            try #require(actual.runs.first { $0[PreviewMathSourceAttribute.self] == id }?.link?.relativeString)
        }
        #expect(targets.map { Data($0.utf8) } == [Data("/caf%C3%A9".utf8), Data("/cafe%CC%81".utf8)])
    }

    @Test(arguments: ["`$x$`", "```\n$x$\n```", "[$x$]: /unused"])
    func codeAndInvisibleDefinitionsNeverMintAnAttachment(_ source: String) throws {
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, replacements: [occurrence])
        let actual = try PreviewMathMarkupParser(input: input, attachments: [occurrence.id: attachment(occurrence.id)])
            .attributedString(for: source)
        #expect(scalarText(actual).utf8.elementsEqual(source.utf8))
        #expect(actual.runs.allSatisfy { $0.textual.attachment == nil && $0[PreviewMathSourceAttribute.self] == nil })
    }

    @Test func inlineHTMLTokensStayLiteralWhileTheirOrdinaryContentMayContainMath() throws {
        let source = "<span>$x$</span>"
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, replacements: [occurrence])
        let actual = try PreviewMathMarkupParser(input: input, attachments: [occurrence.id: attachment(occurrence.id)])
            .attributedString(for: source)
        #expect(scalarText(actual).utf8.elementsEqual("<span>\u{FFFC}</span>".utf8))
        #expect(actual.runs
            .contains { $0[PreviewMathSourceAttribute.self] == occurrence.id && $0.textual.attachment != nil })
    }

    @Test(arguments: ["0Q", "999Q", "0X"])
    func entityDecodedMarkerForgeriesRecoverTheWholeVisibleBlock(_ suffix: String) throws {
        let source = "&#77;TEQ" + namespace + "Z" + suffix + " then $x$"
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, replacements: [occurrence], namespace: namespace)
        let actual = try PreviewMathMarkupParser(input: input, attachments: [occurrence.id: attachment(occurrence.id)])
            .attributedString(for: source)
        #expect(scalarText(actual).utf8.elementsEqual(source.utf8))
        #expect(actual.runs.allSatisfy { $0.textual.attachment == nil })
    }

    @Test func missingDuplicatedAndForeignProvenanceAreRejectedBeforeRestoration() throws {
        let source = "$x$"
        let occurrence = try replacement(in: source)
        let input = try PreviewMathInput(source: source, replacements: [occurrence], namespace: namespace)
        let parser = PreviewMathMarkupParser(input: input, attachments: [occurrence.id: attachment(occurrence.id)])
        let native = AttributedStringMarkdownParser(
            baseURL: nil,
            options: .init(appliesSourcePositionAttributes: true),
            syntaxExtensions: []
        )
        let actual = try native.attributedString(for: input.rewritten)
        var duplicate = actual
        duplicate.append(actual)
        #expect(throws: PreviewMathInput.Failure.self) { try parser.restore(duplicate) }
        #expect(throws: PreviewMathInput.Failure.self) { try parser.restore(AttributedString("missing")) }
        #expect(throws: PreviewMathInput.Failure.self) { try parser.restore(AttributedString(input.rewritten)) }
        let foreignSource = "longer prefix " + input.rewritten
        let foreign = try native.attributedString(for: foreignSource)
        #expect(throws: PreviewMathInput.Failure.self) { try parser.restore(foreign) }
        let wrongSource = "changed $x$"
        #expect(try scalarText(parser.attributedString(for: wrongSource)).utf8.elementsEqual(wrongSource.utf8))
    }
}

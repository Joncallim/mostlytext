import Foundation
@testable import MarkdownEngine
import Testing

struct FrontMatterTests {
    // MARK: - Extraction

    @Test func extractsValidFrontMatter() throws {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.validFrontMatter)
        let result = try #require(extraction)

        #expect(result.raw.contains("title: Hello"))
        #expect(result.closingLineNumber == 8)
        #expect(result.body.hasPrefix("# Body"))
    }

    @Test func malformedYAMLStillFrontMatter() throws {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.malformedFrontMatter)
        let result = try #require(extraction)

        #expect(result.raw.contains(": : invalid"))
        #expect(result.closingLineNumber == 3)
        #expect(result.body.hasPrefix("# Body"))
    }

    @Test func nonMappingRootStillFrontMatter() throws {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.nonMappingFrontMatter)
        let result = try #require(extraction)

        #expect(result.raw.contains("- one"))
        #expect(result.closingLineNumber == 4)
    }

    @Test func dotCloserAccepted() throws {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.dotCloserFrontMatter)
        let result = try #require(extraction)

        #expect(result.closingLineNumber == 3)
    }

    @Test func emptyFrontMatterBlock() throws {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.emptyFrontMatter)
        let result = try #require(extraction)

        #expect(result.raw.isEmpty)
        #expect(result.closingLineNumber == 2)
        #expect(result.body.hasPrefix("# Body"))
    }

    @Test func noCloserMeansNoFrontMatter() {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.noCloserFrontMatter)

        #expect(extraction == nil)
    }

    @Test func bomPrefixedFrontMatterDetected() throws {
        let extraction = FrontMatterExtractor.extract(from: Fixtures.bomPrefixedFrontMatter)
        let result = try #require(extraction)

        #expect(result.raw.contains("title: Hello"))
        #expect(result.closingLineNumber == 3)
        #expect(result.body.hasPrefix("# Body"))
    }

    @Test func trailingWhitespaceOnDelimiterIgnored() {
        let text = "--- \ntitle: Hello\n---\n# Body"
        let extraction = FrontMatterExtractor.extract(from: text)

        #expect(extraction != nil)
        #expect(extraction?.closingLineNumber == 3)
    }

    @Test func emptyTextHasNoFrontMatter() {
        let extraction = FrontMatterExtractor.extract(from: "")

        #expect(extraction == nil)
    }

    @Test func leadingWhitespaceOnDelimiterRejected() {
        let text = "   ---\ntitle: Hello\n---\n# Body"
        let extraction = FrontMatterExtractor.extract(from: text)

        #expect(extraction == nil)
    }

    @Test func crlfLineEndingsDoNotLeakCarriageReturn() throws {
        let text = "---\r\ntitle: Hello\r\n---\r\n# Body"
        let extraction = try #require(FrontMatterExtractor.extract(from: text))

        #expect(extraction.raw.contains("\r") == false)
        #expect(extraction.body.hasPrefix("# Body"))
    }

    // MARK: - YAML conversion

    @Test func parsesMappingToValues() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.validFrontMatter, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.values != nil)
        #expect(frontMatter.values?["title"] == .string("Hello"))
        #expect(frontMatter.values?["count"] == .int(42))
        #expect(frontMatter.values?["enabled"] == .bool(true))
        #expect(frontMatter.values?["tags"] == .array([.string("swift"), .string("markdown")]))
    }

    @Test func parsesFloatingPointToNumber() async throws {
        let text = """
        ---
        price: 3.14
        ---
        # Body
        """
        let engine = ParseEngine()
        let document = try await engine.parse(text, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.values?["price"] == .number(3.14))
    }

    @Test func unsignedNSNumberInRangeConvertsToInt() {
        let engine = ParseEngine()

        let u64 = engine.convertNSNumber(NSNumber(value: UInt64(42)))
        #expect(u64 == .int(42))

        let uint = engine.convertNSNumber(NSNumber(value: UInt(42)))
        #expect(uint == .int(42))

        let uint8 = engine.convertNSNumber(NSNumber(value: UInt8(255)))
        #expect(uint8 == .int(255))
    }

    @Test func unsignedNSNumberOutOfRangeFallsBackToNumber() {
        let engine = ParseEngine()
        let number = NSNumber(value: UInt64.max)

        let value = engine.convertNSNumber(number)

        #expect(value == .number(number.doubleValue))
    }

    @Test func signedNegativeNSNumberConvertsToInt() {
        let engine = ParseEngine()
        let value = engine.convertNSNumber(NSNumber(value: Int64(-42)))

        #expect(value == .int(-42))
    }

    /// Value 9_999_999_999_999_999 fits in Int64; this tests that large
    /// in-range integers survive the full Yams→parse pipeline unchanged.
    @Test func largeIntegerIsPreserved() async throws {
        let text = """
        ---
        id: 9999999999999999
        ---
        # Body
        """
        let engine = ParseEngine()
        let document = try await engine.parse(text, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.values?["id"] == .int(9_999_999_999_999_999))
    }

    @Test func malformedYAMLProducesNilValues() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.malformedFrontMatter, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.values == nil)
    }

    @Test func nonMappingRootProducesNilValues() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.nonMappingFrontMatter, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.values == nil)
    }

    @Test func bodyLessDocumentAfterFrontMatter() async throws {
        let text = "---\nkey: val\n---\n"
        let engine = ParseEngine()
        let document = try await engine.parse(text, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.values?["key"] == .string("val"))
        #expect(document.body.isEmpty)
        #expect(document.blocks.isEmpty)
        #expect(document.headings.isEmpty)
    }

    // MARK: - Line numbers

    @Test func frontMatterLineRangeIncludesDelimiters() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.validFrontMatter, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.lineRange == 1 ... 8)
    }

    @Test func bodyLineOffsetEqualsClosingDelimiterLine() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.validFrontMatter, revision: 1)

        #expect(document.bodyLineOffset == 8)
        #expect(document.body.hasPrefix("# Body"))
    }

    @Test func blocksStartAfterFrontMatter() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.validFrontMatter, revision: 1)

        let heading = try #require(document.headings.first)
        #expect(heading.lineRange == 9 ... 9)
    }

    @Test func loneOpenerIsThematicBreak() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.noCloserFrontMatter, revision: 1)

        #expect(document.frontMatter == nil)
        #expect(document.blocks.contains(where: { $0.kind == .thematicBreak }))
    }

    @Test func bomPrefixedFrontMatterDoesNotLeakIntoBody() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse(Fixtures.bomPrefixedFrontMatter, revision: 1)

        let frontMatter = try #require(document.frontMatter)
        #expect(frontMatter.lineRange == 1 ... 3)
        #expect(document.bodyLineOffset == 3)
        #expect(document.body.hasPrefix("# Body"))
        #expect(!document.blocks.contains(where: { $0.kind == .thematicBreak }))
    }

    @Test func aBlankLineAfterTheOpenerMakesItAThematicBreakNotFrontMatter() async throws {
        let text = "---\n\n# Intro\n\nSome text here.\n\n---\n\nMore\n"
        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.frontMatter == nil)
        #expect(document.headings.map(\.title) == ["Intro"])
        #expect(document.blocks.contains(where: { $0.kind == .thematicBreak }))
    }

    @Test func anEmptyFrontMatterBlockIsStillFrontMatter() async throws {
        let document = try await ParseEngine().parse("---\n---\n# Body\n", revision: 1)

        #expect(document.frontMatter?.lineRange == 1 ... 2)
    }
}

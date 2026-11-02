import ExportService
@testable import MacDown2
import MarkdownEngine
import Testing

struct FrozenExportParseTests {
    @Test func theExactSourceAndNondefaultPolicyReuseTheAcceptedDocument() async throws {
        let source = "@Note {\n雪\n}\n"
        let options = MarkdownParseOptions(blockDirectives: true)
        let parsed = try await ParseEngine().parse(source, options: options, revision: 3)
        let frozen = FrozenExportParse(text: source, revision: 3, document: parsed, options: options)
        #expect(try await frozen.parse(source, options: options, revision: 3) == parsed)
    }

    @Test func canonicallyEquivalentSourceCannotBorrowTheParse() async throws {
        let source = "caf\u{E9}"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let frozen = FrozenExportParse(text: source, revision: 1, document: parsed)
        await #expect(throws: ExportError.self) {
            try await frozen.parse("cafe\u{301}", options: .default, revision: 1)
        }
    }

    @Test func anotherRevisionCannotBorrowTheParse() async throws {
        let parsed = try await ParseEngine().parse("# Source", revision: 1)
        let frozen = FrozenExportParse(text: "# Source", revision: 1, document: parsed)
        await #expect(throws: ExportError.self) {
            try await frozen.parse("# Source", options: .default, revision: 2)
        }
    }

    @Test func anotherPolicyCannotBorrowTheParse() async throws {
        let parsed = try await ParseEngine().parse("# Source", revision: 1)
        let frozen = FrozenExportParse(text: "# Source", revision: 1, document: parsed)
        await #expect(throws: ExportError.self) {
            try await frozen.parse("# Source", options: MarkdownParseOptions(blockDirectives: true), revision: 1)
        }
    }

    @Test func inconsistentDocumentMetadataIsRejected() async throws {
        let parsed = try await ParseEngine().parse("# Source", revision: 1)
        let wrongRevision = FrozenExportParse(text: "# Source", revision: 2, document: parsed)
        await #expect(throws: ExportError.self) {
            try await wrongRevision.parse("# Source", options: .default, revision: 2)
        }
        let options = MarkdownParseOptions(blockDirectives: true)
        let wrongPolicy = FrozenExportParse(text: "# Source", revision: 1, document: parsed, options: options)
        await #expect(throws: ExportError.self) {
            try await wrongPolicy.parse("# Source", options: options, revision: 1)
        }
    }

    @Test func ordinaryCompositionConsumesOnceWhileTheDisabledFallbackCanRepeat() async throws {
        let source = "# Source"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let single = FrozenExportParse(text: source, revision: 1, document: parsed, releaseAfterUse: true)
        #expect(try await single.parse(source, options: .default, revision: 1) == parsed)
        await #expect(throws: ExportError.self) { try await single.parse(source, options: .default, revision: 1) }
        let repeating = FrozenExportParse(text: source, revision: 1, document: parsed)
        #expect(try await repeating.parse(source, options: .default, revision: 1) == parsed)
        #expect(try await repeating.parse(source, options: .default, revision: 1) == parsed)
    }

    @Test func aCancelledConsumerCannotBorrowTheParse() async throws {
        let parsed = try await ParseEngine().parse("# Source", revision: 1)
        let frozen = FrozenExportParse(text: "# Source", revision: 1, document: parsed)
        let consumer = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await frozen.parse("# Source", options: .default, revision: 1)
        }
        await #expect(throws: CancellationError.self) { try await consumer.value }
    }
}

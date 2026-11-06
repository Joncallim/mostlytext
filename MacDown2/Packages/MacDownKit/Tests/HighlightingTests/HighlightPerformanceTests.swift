import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

/// Debug builds (the CI `swift test` configuration) keep generous DOCUMENTATION
/// ceilings, recalibrated 2026-07-23 for the `macos-26` runner where E06's
/// parse-heavy tests contend for cores. Release builds
/// (`swift test -c release --filter HighlightPerformanceTests --no-parallel`)
/// enforce the ceilings below, which sit at ~2x the measured Release numbers
/// recorded in `planning/epic-22-implementation.md` (Slice 10s) — regression
/// guards, not the E05 product budgets. Two E05 budgets are *not* met by these
/// measurements and are reported rather than asserted away: see `ReleaseCeiling`.
@MainActor
struct HighlightPerformanceTests {
    /// Release ceilings. Measured on Apple silicon, 1 MB Markdown, serial run:
    /// full highlight 0.25 s (E05 budget 500 ms: met); full parse 0.20 s; an
    /// incremental reparse after a one-character edit 0.19 s — the same cost as
    /// a full parse (it scales linearly with document size and does not reuse
    /// the old tree), so E05's 50 ms keystroke budget is NOT met for 1 MB
    /// Markdown at the parser level. The cause is the upstream block grammar,
    /// not the edit wiring: see `MarkdownTreeReuseTests`. Neon does not move
    /// this off the main thread for a typing-sized edit that ends before
    /// UTF-16 offset 1,048,576 (`BackgroundingLanguageLayerTree`'s
    /// `synchronousDocumentSize`): it reparses synchronously on the main
    /// actor. The 8 ms main-thread budget applies to viewport-slice work,
    /// covered by `EditorPerformanceTests`, not to a whole-document parse.
    private enum ReleaseCeiling {
        static let fullHighlight: Duration = .milliseconds(500)
        static let fullParse: Duration = .milliseconds(400)
        static let incrementalReparse: Duration = .milliseconds(400)
    }

    private static var isRelease: Bool {
        #if DEBUG
            false
        #else
            true
        #endif
    }

    @Test func fullHighlight1MB() throws {
        let text = Fixtures.markdownRepeating(
            line: "# Heading\n\nSome `code` and **bold** text.\n\n",
            totalBytes: 1_000_000
        )
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let start = ContinuousClock().now
        let parser = Parser()
        try parser.setLanguage(config.language)
        let parserReady = ContinuousClock().now
        guard let tree = parser.parse(text),
              let rootNode = tree.rootNode,
              let query = config.queries[.highlights]
        else {
            Issue.record("Failed to parse or load query")
            return
        }
        let parseReady = ContinuousClock().now
        let cursor = query.execute(node: rootNode, in: tree)
        cursor.setRange(NSRange(location: 0, length: (text as NSString).length))
        _ = cursor.highlights()
        let duration = ContinuousClock().now - start
        // Observe the original total without subtracting setup, parse, query or result disposal.
        // Emit only after the timed interval so diagnostic output cannot dominate that measurement.
        print("HIGHLIGHT_PHASE sourceUTF8=\(text.utf8.count) setup=\(parserReady - start) " +
            "parse=\(parseReady - parserReady) query=\(duration - (parseReady - start)) total=\(duration)")

        #expect(
            duration < (Self.isRelease ? ReleaseCeiling.fullHighlight : .seconds(8)),
            "Full 1 MB highlight took \(duration)"
        )
    }

    @Test func incrementalKeystroke1MB() throws {
        let text = Fixtures.markdownRepeating(
            line: "# Heading\n\nSome `code` and **bold** text.\n\n",
            totalBytes: 1_000_000
        )
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let parser = Parser()
        try parser.setLanguage(config.language)
        guard let editedTree = parser.parse(text) else {
            Issue.record("Initial parse failed")
            return
        }

        // Simulate inserting a character near the middle.
        let nsText = text as NSString
        let editLocation = nsText.length / 2
        let newText = nsText.replacingCharacters(in: NSRange(location: editLocation, length: 0), with: "x")

        // SwiftTreeSitter feeds the parser UTF-16 text, so tree-sitter byte
        // offsets and point columns are UTF-16 code units * 2 (not the unit
        // count, even for ASCII). Mis-scaled offsets describe an edit at the
        // wrong place, the old tree cannot be reused, and the "incremental"
        // reparse silently degrades to a full parse (issue #203).
        let bytesPerUnit = 2
        let startByte = editLocation * bytesPerUnit
        let oldEndByte = startByte
        let newEndByte = (editLocation + 1) * bytesPerUnit

        let startPoint = point(for: editLocation, in: text)
        let oldEndPoint = startPoint
        let newEndPoint = point(for: editLocation + 1, in: newText)

        let inputEdit = InputEdit(
            startByte: startByte,
            oldEndByte: oldEndByte,
            newEndByte: newEndByte,
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint
        )
        editedTree.edit(inputEdit)

        let start = ContinuousClock().now
        _ = parser.parse(tree: editedTree, string: newText)
        let duration = ContinuousClock().now - start

        #expect(
            duration < (Self.isRelease ? ReleaseCeiling.incrementalReparse : .seconds(8)),
            "Incremental keystroke took \(duration)"
        )
    }

    /// Control for the Markdown measurement above: with correctly scaled edit
    /// offsets a grammar whose scanner permits reuse (JSON) reparses a 1 MB
    /// document after a one-character insert far below a full parse, and the
    /// edit reports a single changed range. This proves the harness exercises
    /// real tree reuse, so the Markdown block grammar's lack of speed-up is a
    /// grammar property rather than a measurement artefact.
    @Test func incrementalReparseReusesTheOldTreeForAReusableGrammar() throws {
        let text = Fixtures.markdownRepeating(line: "{\"a\": [1, 2, 3], \"b\": \"text\"}\n", totalBytes: 1_000_000)
        let config = try #require(GrammarRegistry().configuration(for: "json"))
        let parser = Parser()
        try parser.setLanguage(config.language)
        let tree = try #require(parser.parse(text))

        let nsText = text as NSString
        let location = nsText.length / 2
        let newText = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: " ")
        let startPoint = point(for: location, in: text)
        tree.edit(InputEdit(
            startByte: location * 2,
            oldEndByte: location * 2,
            newEndByte: (location + 1) * 2,
            startPoint: startPoint,
            oldEndPoint: startPoint,
            newEndPoint: point(for: location + 1, in: newText)
        ))
        let reparsed = try #require(parser.parse(tree: tree, string: newText))

        #expect(tree.changedRanges(from: reparsed).count <= 1, "only the edited region may change")
    }

    @Test func mainThreadParseBudgetDocumented() throws {
        let text = Fixtures.markdownRepeating(
            line: "# Heading\n\nSome `code` and **bold** text.\n\n",
            totalBytes: 1_000_000
        )
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let parser = Parser()
        try parser.setLanguage(config.language)

        let start = ContinuousClock().now
        _ = parser.parse(text)
        let duration = ContinuousClock().now - start

        #expect(
            duration < (Self.isRelease ? ReleaseCeiling.fullParse : .seconds(8)),
            "Full 1 MB parse took \(duration)"
        )
    }

    // MARK: - Helpers

    /// Returns the tree-sitter `Point` for a UTF-16 offset; the column is in
    /// bytes (UTF-16 units * 2), matching the byte offsets above.
    private func point(for utf16Offset: Int, in text: String) -> Point {
        let nsText = text as NSString
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        nsText.getLineStart(&lineStart,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: utf16Offset, length: 0))

        let preceding = nsText.substring(with: NSRange(location: 0, length: lineStart)) as NSString
        let row = preceding.components(separatedBy: "\n").count - 1
        let column = utf16Offset - lineStart

        return Point(row: row, column: column * 2)
    }
}

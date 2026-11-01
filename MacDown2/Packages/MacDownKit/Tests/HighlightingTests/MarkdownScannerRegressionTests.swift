import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

/// Validate the patched vendored scanner through the same UTF-16 parser used
/// by Highlighting. These controls start no application or mounted editor.
@MainActor
struct MarkdownScannerRegressionTests {
    @Test(arguments: [0, 1, 32, 253, 254, 255, 300, 512])
    func nestedQuotesRetainCompleteInput(depth: Int) throws {
        let text = String(repeating: "> ", count: depth) + "Café 🐈\n\n# After\n"
        let (_, tree) = try parse(text)
        let root = try #require(tree.rootNode)
        #expect(root.byteRange == 0 ..< UInt32(text.utf16.count * 2))
        #expect(!root.hasError)
        #expect(try signature(tree).contains { $0.kind == "atx_heading" })
    }

    @Test(arguments: [1, 32, 253, 254, 255, 300])
    func editsMatchFreshParseAcrossNestingLimit(depth: Int) throws {
        let original = String(repeating: "> ", count: depth) + "Café 🐈\n"
        let (parser, tree) = try parse(original)
        let location = original.utf16.count - 1
        let point = Point(row: 0, column: location * 2)
        let replacement = " and tea"
        tree.edit(InputEdit(
            startByte: location * 2,
            oldEndByte: location * 2,
            newEndByte: (location + replacement.utf16.count) * 2,
            startPoint: point,
            oldEndPoint: point,
            newEndPoint: Point(row: 0, column: (location + replacement.utf16.count) * 2)
        ))
        let changed = (original as NSString).replacingCharacters(
            in: NSRange(location: location, length: 0), with: replacement
        )
        let incremental = try #require(parser.parse(tree: tree, string: changed))
        let (_, fresh) = try parse(changed)
        #expect(try signature(incremental) == signature(fresh))
    }

    @Test(arguments: [".", ")"])
    func orderedListsKeepBothItems(delimiter: String) throws {
        let text = "1\(delimiter) Café\n2\(delimiter) Tea\n"
        let (_, tree) = try parse(text)
        let nodes = try signature(tree)
        #expect(nodes.count { $0.kind == "list_item" } == 2)
        #expect(try #require(tree.rootNode).hasError == false)
    }

    @Test(arguments: ["é", "漢", "🐈", "١", "９"])
    func unicodeAfterDigitRemainsParagraph(suffix: String) throws {
        let text = "1\(suffix). ordinary text\n"
        let (_, tree) = try parse(text)
        let nodes = try signature(tree)
        #expect(!nodes.contains { $0.kind == "list_item" })
        #expect(nodes.contains { $0.kind == "paragraph" })
        #expect(try #require(tree.rootNode).byteRange.upperBound == UInt32(text.utf16.count * 2))
    }

    @Test(arguments: [".", ")"])
    func noninterruptingListMarkerPreservesParagraph(delimiter: String) throws {
        let text = "paragraph\n22\(delimiter) stays in the paragraph\n"
        let (_, tree) = try parse(text)
        #expect(try !signature(tree).contains { $0.kind == "list_item" })
    }

    private func parse(_ text: String) throws -> (Parser, MutableTree) {
        let configuration = try #require(GrammarRegistry().configuration(for: "markdown"))
        let parser = Parser()
        try parser.setLanguage(configuration.language)
        return try (parser, #require(parser.parse(text)))
    }

    private struct NodeSignature: Equatable {
        let kind: String?
        let bytes: Range<UInt32>
        let points: Range<Point>
        let childCount: Int
        let named: Bool
        let missing: Bool
    }

    /// Iterative traversal also checks anonymous markers, byte/point ranges and
    /// sibling structure without recursing on the test process's stack.
    private func signature(_ tree: MutableTree) throws -> [NodeSignature] {
        var pending = try [#require(tree.rootNode)]
        var result: [NodeSignature] = []
        while let node = pending.popLast() {
            result.append(NodeSignature(
                kind: node.nodeType,
                bytes: node.byteRange,
                points: node.pointRange,
                childCount: node.childCount,
                named: node.isNamed,
                missing: node.isMissing
            ))
            for index in (0 ..< node.childCount).reversed() {
                try pending.append(#require(node.child(at: index)))
            }
        }
        return result
    }
}

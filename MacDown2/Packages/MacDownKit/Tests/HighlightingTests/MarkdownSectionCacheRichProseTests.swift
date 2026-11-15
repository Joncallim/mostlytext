import Foundation
@testable import Highlighting
import Testing

@MainActor
@Suite(.serialized)
struct MarkdownSectionCacheRichProseTests {
    private struct EditCase {
        let name: String
        let anchor: String
        let offset: Int
        let length: Int
        let replacement: String
    }

    @Test(.timeLimit(.minutes(4)))
    // swiftlint:disable:next function_body_length
    func boundedHeadingAndInlineEditsMatchFullParse() throws {
        let filler = HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 530_000)
        var source =
            "# alphaStart heading\n\nCRLF_MARKER\r\ncafé 😊 **bold**\r\n\r\n"
                + filler + "\n\n## alphaMiddle heading\n\n" + filler
                + "\n\n`alphaEnd` and **uniqueTailReplacementMarker**\n"
        let registry = GrammarRegistry()
        let first = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        var cache = try MarkdownSectionCache(source: source, snapshot: first)
        let edits: [EditCase] = [
            .init(name: "begin-word", anchor: "alphaStart", offset: 5, length: 0, replacement: "X"),
            .init(name: "middle-word", anchor: "alphaMiddle", offset: 5, length: 0, replacement: "Y"),
            .init(name: "end-word", anchor: "alphaEnd", offset: 5, length: 0, replacement: "Z"),
            .init(name: "begin-delete", anchor: "alphaXStart", offset: 5, length: 1, replacement: ""),
            .init(name: "word-boundary", anchor: "alphaYMiddle", offset: 12, length: 0, replacement: " "),
            .init(
                name: "replacement-shrink", anchor: "uniqueTailReplacementMarker", offset: 0, length: 27,
                replacement: "uniqueTail"
            ),
            .init(
                name: "replacement-grow", anchor: "uniqueTail", offset: 0, length: 10,
                replacement: "uniqueTailReplacementMarker"
            ),
        ]
        for edit in edits {
            let old = source as NSString
            let anchor = old.range(of: edit.anchor)
            try #require(anchor.location != NSNotFound, "Missing anchor: \(edit.name)")
            let range = NSRange(location: anchor.location + edit.offset, length: edit.length)
            let viewport = NSRange(
                location: max(0, anchor.location - 8),
                length: min(200, old.length - max(0, anchor.location - 8))
            )
            let window = try #require(
                cache.select(
                    source: old, edit: range,
                    replacement: edit.replacement, visible: viewport
                ), "Rejected local edit: \(edit.name)"
            )
            source = old.replacingCharacters(in: range, with: edit.replacement)
            let content = (source as NSString).substring(with: window.new)
            let local = try MarkdownSectionParser.snapshot(source: content, registry: registry)
            print(
                "RICH_PROSE case=\(edit.name) window=\(window.new.length) "
                    + "oldType=\(cache.visibleSections(viewport).first?.node.nodeType ?? "none") "
                    + "rootChildren=\(local.rootSnapshot.tree.rootNode?.childCount ?? -1) "
                    + "newType=\(local.rootSnapshot.tree.rootNode?.child(at: 0)?.nodeType ?? "none")"
            )
            try cache.replace(
                window, with: local, content: content,
                delta: (edit.replacement as NSString).length - range.length
            )
            let changedViewport = NSRange(
                location: viewport.location,
                length: min(200, (source as NSString).length - viewport.location)
            )
            let full = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            let oracle = try MarkdownSectionCache(source: source, snapshot: full)
            #expect(
                try cache.tokens(in: changedViewport) == oracle.tokens(in: changedViewport),
                "Oracle mismatch: \(edit.name)"
            )
        }
        let current = source as NSString
        let unicode = current.range(of: "café")
        let crlf = current.range(of: "CRLF_MARKER\r\n")
        let heading = current.range(of: "alphaStart")
        try #require(
            unicode.location != NSNotFound && crlf.location != NSNotFound
                && heading.location != NSNotFound
        )
        #expect(
            cache.select(
                source: current, edit: NSRange(location: unicode.location + 3, length: 1),
                replacement: "e\u{301}", visible: unicode
            ) == nil
        )
        #expect(
            cache.select(
                source: current, edit: NSRange(location: crlf.location + 11, length: 2),
                replacement: "\n", visible: crlf
            ) == nil
        )
        #expect(
            cache.select(
                source: current, edit: NSRange(location: heading.location + 5, length: 0),
                replacement: "\n", visible: heading
            ) == nil
        )
    }

    @Test func aForbiddenCharacterBeforeCRLFIsNotDroppedFromTheAdmissionCheck() throws {
        let registry = GrammarRegistry()
        for (line, expectedAdmission) in [("hello", true), ("hello[", false)] {
            let source = "# heading\n\n\(line)\r\n\n# tail\n"
            let old = source as NSString
            let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            let cache = try MarkdownSectionCache(source: source, snapshot: snapshot)
            let found = old.range(of: "hello")
            try #require(found.location != NSNotFound)
            let edit = NSRange(location: found.location + 2, length: 0)
            let visible = NSRange(location: found.location, length: (line as NSString).length)
            #expect((cache.select(source: old, edit: edit, replacement: "X", visible: visible) != nil)
                == expectedAdmission)
        }
    }
}

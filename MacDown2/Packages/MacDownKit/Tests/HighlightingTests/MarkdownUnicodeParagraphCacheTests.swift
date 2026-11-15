import Foundation
@testable import Highlighting
import Testing

@MainActor
@Suite("Bounded Unicode paragraph cache")
struct MarkdownUnicodeParagraphCacheTests {
    private struct Edit {
        let anchor: String
        let offset: Int
        let length: Int
        let replacement: String
    }

    @Test(.timeLimit(.minutes(5)))
    // swiftlint:disable:next function_body_length
    func unicodeThenSameParagraphAndDownstreamEditsMatchFreshFullParse() throws {
        let filler = HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 530_000)
        var source = "# alphaStart heading\n\n## CRLF_MARKER\r\n**café** 😊 **bold**\r\n\r\n"
            + filler + "\n\n## alphaMiddle heading\n\n" + filler
            + "\n\n`alphaEnd` and **uniqueTailReplacementMarker**\n"
        try #require(source.utf8.count >= 1 << 20)
        let registry = GrammarRegistry()
        let initial = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        var cache = try MarkdownSectionCache(source: source, snapshot: initial)
        let edits: [Edit] = [
            .init(anchor: "café", offset: 3, length: 1, replacement: "e\u{301}"),
            .init(anchor: "bold", offset: 2, length: 0, replacement: "X"),
            .init(anchor: "alphaMiddle", offset: 5, length: 0, replacement: "Y"),
        ]
        for (step, edit) in edits.enumerated() {
            let old = source as NSString
            let anchor = old.range(of: edit.anchor)
            try #require(anchor.location != NSNotFound)
            let range = NSRange(location: anchor.location + edit.offset, length: edit.length)
            let visible = Self.window(around: anchor.location, length: old.length)
            let originalEntry = try #require(cache.visibleSections(visible).first {
                NSIntersectionRange($0.globalRange, NSRange(location: range.location, length: 1)).length > 0
            })
            #expect(["paragraph", "section"].contains(originalEntry.node.nodeType))
            let selected = try #require(cache.select(source: old, edit: range,
                                                     replacement: edit.replacement, visible: visible))
            #expect(selected.old.length < MarkdownSectionCache.windowLimit)
            source = old.replacingCharacters(in: range, with: edit.replacement)
            let content = (source as NSString).substring(with: selected.new)
            let local = try MarkdownSectionParser.snapshot(source: content, registry: registry)
            if originalEntry.node.nodeType == "paragraph" {
                let root = try #require(local.rootSnapshot.tree.rootNode)
                let wrapper = try #require(root.child(at: 0))
                let paragraph = try #require(wrapper.child(at: 0))
                #expect(root.childCount == 1 && wrapper.nodeType == "section")
                #expect(wrapper.childCount == 1 && paragraph.nodeType == "paragraph")
                #expect(wrapper.range == NSRange(location: 0, length: (content as NSString).length))
                #expect(paragraph.range == wrapper.range)
            }
            try cache.replace(selected, with: local, content: content,
                              delta: (edit.replacement as NSString).length - range.length)
            let full = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            let oracle = try MarkdownSectionCache(source: source, snapshot: full)
            for later in ["cafe\u{301}", "boXld", "alphaMiddle", "alphaYMiddle", "alphaEnd"] {
                let location = (source as NSString).range(of: later).location
                if location == NSNotFound {
                    continue
                }
                let probe = Self.window(around: location, length: (source as NSString).length)
                #expect(try cache.tokens(in: probe) == oracle.tokens(in: probe),
                        "Full-parse mismatch after step \(step) near \(later)")
            }
        }
    }

    @Test func markdownSyntaxAndIncompleteParagraphWrapperStayOnFullParsePath() throws {
        let registry = GrammarRegistry()
        let longBody = String(repeating: "ordinaryword ", count: 6000)
        for suffix in ["$math$", "[link](url)", "\\escape", "&amp;", "# marker"] {
            let source = "# Heading\n\n**café** 😊 \(suffix) **bold**\r\n\r\n" + longBody
            let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            let cache = try MarkdownSectionCache(source: source, snapshot: snapshot)
            let old = source as NSString
            let found = old.range(of: "café")
            let edit = NSRange(location: found.location + 3, length: 1)
            let visible = Self.window(around: found.location, length: old.length)
            #expect(cache.select(source: old, edit: edit, replacement: "e\u{301}", visible: visible) == nil,
                    "Markdown syntax must keep full fallback: \(suffix)")
        }

        let source = "# Heading\n\n**café** 😊 **bold**\r\n\r\n" + longBody
        let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        var cache = try MarkdownSectionCache(source: source, snapshot: snapshot)
        let old = source as NSString
        let found = old.range(of: "café")
        let edit = NSRange(location: found.location + 3, length: 1)
        let visible = Self.window(around: found.location, length: old.length)
        let selected = try #require(cache.select(source: old, edit: edit,
                                                 replacement: "e\u{301}", visible: visible))
        #expect(selected.old.length < MarkdownSectionCache.windowLimit)
        let originalEntry = try #require(cache.visibleSections(visible).first {
            NSIntersectionRange($0.globalRange, NSRange(location: edit.location, length: 1)).length > 0
        })
        #expect(originalEntry.node.nodeType == "paragraph")
        let updated = old.replacingCharacters(in: edit, with: "e\u{301}")
        let content = (updated as NSString).substring(with: selected.new)
        let local = try MarkdownSectionParser.snapshot(source: content, registry: registry)
        var accepted = cache
        try accepted.replace(selected, with: local, content: content, delta: 1)
        let full = try MarkdownSectionParser.snapshot(source: updated, registry: registry)
        let oracle = try MarkdownSectionCache(source: updated, snapshot: full)
        let updatedVisible = Self.window(around: found.location, length: (updated as NSString).length)
        #expect(try accepted.tokens(in: updatedVisible) == oracle.tokens(in: updatedVisible))
        let malformed = (content as NSString).replacingCharacters(
            in: NSRange(location: (content as NSString).length - 2, length: 2), with: "\n\n"
        )
        try #require((malformed as NSString).length == selected.new.length)
        let nonFullWidth = try MarkdownSectionParser.snapshot(source: malformed, registry: registry)
        let root = try #require(nonFullWidth.rootSnapshot.tree.rootNode)
        let wrapper = try #require(root.child(at: 0))
        let paragraph = try #require(wrapper.child(at: 0))
        #expect(paragraph.range != wrapper.range)
        do {
            try cache.replace(selected, with: nonFullWidth, content: malformed, delta: 1)
            Issue.record("A paragraph that does not cover the local source was admitted")
        } catch MarkdownSectionCache.CacheError.sectionShapeChanged {
            // Expected: do not silently map a partial paragraph onto the old entry.
        }
    }

    private static func window(around location: Int, length: Int) -> NSRange {
        let lower = max(0, location - 12)
        return NSRange(location: lower, length: min(120, length - lower))
    }
}

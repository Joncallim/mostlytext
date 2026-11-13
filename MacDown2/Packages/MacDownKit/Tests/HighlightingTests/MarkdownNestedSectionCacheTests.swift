import Foundation
@testable import Highlighting
import Neon
import SwiftTreeSitterLayer
import Testing

@MainActor
@Suite("Nested Markdown section cache")
struct MarkdownNestedSectionCacheTests {
    @Test(.timeLimit(.minutes(2)))
    func manyParagraphsInOneLeafStillSelectABoundedEdit() throws {
        let paragraph = String(repeating: "ordinaryword beta ", count: 15) + "\n\n"
        let padding = String(repeating: paragraph, count: 2000)
        let source = "# One long leaf\n\n" + padding + "midtarget beta\n\n" + padding
            + "tailtarget beta\n\n"
        #expect(source.utf8.count > 1024 * 1024)
        let registry = GrammarRegistry()
        let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        var cache = try MarkdownSectionCache(source: source, snapshot: snapshot)
        let old = source as NSString
        let word = old.range(of: "midtarget")
        let edit = NSRange(location: word.location + 3, length: 0)
        let visible = NSRange(location: word.location, length: 40)
        let window = try #require(cache.select(source: old, edit: edit,
                                               replacement: "X", visible: visible))
        #expect(window.old.length < 128)
        let changed = old.replacingCharacters(in: edit, with: "X")
        let content = (changed as NSString).substring(with: window.new)
        let local = try MarkdownSectionParser.snapshot(source: content, registry: registry)
        try cache.replace(window, with: local, content: content, delta: 1)
        let fresh = try MarkdownSectionParser.snapshot(source: changed, registry: registry)
        let expanded = NSRange(location: visible.location, length: visible.length + 1)
        let expected = try fresh.highlights(in: expanded, provider: changed.predicateTextProvider)
            .map { Token(name: $0.name, range: NSIntersectionRange($0.range, expanded)) }
            .filter { $0.range.length > 0 }
        let actual = try cache.tokens(in: expanded)
        #expect(signatures(actual) == signatures(expected))

        let revised = changed as NSString
        let tail = revised.range(of: "tailtarget")
        let tailEdit = NSRange(location: tail.location + 4, length: 0)
        let tailVisible = NSRange(location: tail.location, length: 15)
        let tailWindow = try #require(cache.select(source: revised, edit: tailEdit,
                                                   replacement: "Y", visible: tailVisible))
        #expect(tailWindow.old.length < 128)
        let twiceChanged = revised.replacingCharacters(in: tailEdit, with: "Y")
        let tailContent = (twiceChanged as NSString).substring(with: tailWindow.new)
        let tailLocal = try MarkdownSectionParser.snapshot(source: tailContent, registry: registry)
        try cache.replace(tailWindow, with: tailLocal, content: tailContent, delta: 1)
        let twiceFresh = try MarkdownSectionParser.snapshot(source: twiceChanged, registry: registry)
        let tailExpanded = NSRange(location: tailVisible.location, length: tailVisible.length + 1)
        let tailExpected = try twiceFresh.highlights(in: tailExpanded,
                                                     provider: twiceChanged.predicateTextProvider)
            .map { Token(name: $0.name, range: NSIntersectionRange($0.range, tailExpanded)) }
            .filter { $0.range.length > 0 }
        #expect(try signatures(cache.tokens(in: tailExpanded)) == signatures(tailExpected))
    }

    @Test func parentChildAndGrandchildEditsMatchFreshFullParse() throws {
        let registry = GrammarRegistry()
        let original = "# Parent\n\nalphatarget beta\n\n## Child\n\ngammatarget beta\n\n"
            + "### Grandchild\n\ndeltatarget beta\n\n"
            + Array(repeating: "## Next\n\npadding words\n\n", count: 100).joined()
        var source = original
        let initial = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        var cache = try MarkdownSectionCache(source: source, snapshot: initial)
        for needle in ["alphatarget", "gammatarget", "deltatarget"] {
            let old = source as NSString
            let word = old.range(of: needle)
            try #require(word.location != NSNotFound)
            let edit = NSRange(location: word.location + 5, length: 0)
            let visible = NSRange(location: max(0, edit.location - 8), length: 90)
            let window = try #require(cache.select(source: old, edit: edit,
                                                   replacement: "X", visible: visible))
            #expect(window.old.length < 1024)
            source = old.replacingCharacters(in: edit, with: "X")
            let local = (source as NSString).substring(with: window.new)
            let localSnapshot = try MarkdownSectionParser.snapshot(source: local, registry: registry)
            try cache.replace(window, with: localSnapshot, content: local, delta: 1)

            let fresh = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            let shifted = NSRange(location: visible.location, length: visible.length + 1)
            let expected = try fresh.highlights(in: shifted, provider: source.predicateTextProvider)
                .map { Token(name: $0.name, range: NSIntersectionRange($0.range, shifted)) }
                .filter { $0.range.length > 0 }
            #expect(try signatures(cache.tokens(in: shifted)) == signatures(expected))
        }
    }

    private func signatures(_ tokens: [Token]) -> [String] {
        tokens.map { "\($0.name):\($0.range.location):\($0.range.length)" }.sorted()
    }
}

import Foundation
@testable import Highlighting
import Neon
import SwiftTreeSitterLayer
import Testing

@MainActor
@Suite("Nested Markdown section cache")
struct MarkdownNestedSectionCacheTests {
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

import Foundation
@testable import Highlighting
import Neon
import SwiftTreeSitterLayer
import Testing

@MainActor
@Suite("Markdown bounded structural heading cache")
struct MarkdownStructuralHeadingCacheTests {
    @Test(.timeLimit(.minutes(3)))
    // swiftlint:disable:next function_body_length
    func headingNewlineAndCRLFWindows() throws {
        let filler = HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 530_000)
        let source = "# alphaStart heading\n\n## CRLF_MARKER\r\n**café** 😊 **bold**\r\n\r\n"
            + filler + "\n\n## alphaMiddle heading\n\n" + filler
            + "\n\n`alphaEnd` and **uniqueTailReplacementMarker**\n"
        let registry = GrammarRegistry()
        for (name, marker, oldLength, replacement) in [
            ("heading-newline", "alphaStart", 0, "\n"),
            ("heading-crlf", "CRLF_MARKER\r\n", 2, "\n"),
        ] {
            let old = source as NSString
            let found = old.range(of: marker)
            let location = name == "heading-newline" ? found.location + 5 : found.location + 11
            let edit = NSRange(location: location, length: oldLength)
            let initial = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            var cache = try MarkdownSectionCache(source: source, snapshot: initial)
            let selected = try #require(cache.visibleSections(NSRange(location: location, length: 1)).first)
            let selectedRange = selected.globalRange
            #expect(selected.node.nodeType == "section")
            try #require(selectedRange.length < MarkdownSectionCache.windowLimit)
            guard let selectedWindow = cache.selectStructuralHeading(
                source: old, edit: edit, replacement: replacement,
                visible: NSRange(location: location, length: 1)
            ) else {
                Issue.record("\(name) refused a bounded structural heading window")
                return
            }
            #expect(selectedWindow.old == selectedRange)
            let updated = old.replacingCharacters(in: edit, with: replacement)
            let delta = (replacement as NSString).length - oldLength
            let newRange = NSRange(location: selectedRange.location, length: selectedRange.length + delta)
            let content = (updated as NSString).substring(with: newRange)
            let local = try MarkdownSectionParser.snapshot(source: content, registry: registry)
            let root = try #require(local.rootSnapshot.tree.rootNode)
            #expect(root.childCount == 1)
            #expect(root.child(at: 0)?.nodeType == "section")
            #expect(selectedWindow.new == newRange)
            try cache.replace(selectedWindow, with: local, content: content, delta: delta)
            let full = try MarkdownSectionParser.snapshot(source: updated, registry: registry)
            let oracle = try MarkdownSectionCache(source: updated, snapshot: full)
            let visible = NSRange(
                location: max(0, location - 16),
                length: min(80, (updated as NSString).length - max(0, location - 16))
            )
            let actual = try cache.tokens(in: visible).map { "\($0.name):\($0.range.location):\($0.range.length)" }
                .sorted()
            let expected = try oracle.tokens(in: visible).map { "\($0.name):\($0.range.location):\($0.range.length)" }
                .sorted()
            #expect(actual == expected)
            for later in ["alphaMiddle", "alphaEnd"] {
                let marker = (updated as NSString).range(of: later)
                let range = NSRange(
                    location: marker.location,
                    length: min(80, (updated as NSString).length - marker.location)
                )
                let candidate = try cache.tokens(in: range).map { "\($0.name):\($0.range.location):\($0.range.length)" }
                    .sorted()
                let whole = try oracle.tokens(in: range).map { "\($0.name):\($0.range.location):\($0.range.length)" }
                    .sorted()
                #expect(candidate == whole, "\(name) changed downstream \(later) captures")
            }
        }
    }

    @Test func unsupportedHeadingAndParagraphChangesKeepFullFallback() throws {
        let registry = GrammarRegistry()
        for (source, needle, replacement) in [
            ("# alphaStart heading\n\nbody text\n\n", "# ", "\n"),
            ("# alphaStart heading\n\nbody text\n\n", "alphaStart", "\n##"),
            ("# alpha`Start heading\n\nbody text\n\n", "alpha`Start", "\n"),
            ("body text\r\n\r\n", "\r\n", "\n"),
        ] {
            let old = source as NSString
            let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
            let cache = try MarkdownSectionCache(source: source, snapshot: snapshot)
            let found = old.range(of: needle)
            let edit = NSRange(location: found.location + (needle.hasPrefix("alpha") ? 5 : 0),
                               length: needle == "\r\n" ? 2 : 0)
            #expect(cache.selectStructuralHeading(source: old, edit: edit,
                                                  replacement: replacement,
                                                  visible: NSRange(location: edit.location, length: 1)) == nil)
        }
    }
}

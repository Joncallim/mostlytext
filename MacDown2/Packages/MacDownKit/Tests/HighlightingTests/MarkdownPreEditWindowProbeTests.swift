import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

/// Parser-only proof for a conservative pre-edit window selector. It neither
/// changes Neon's production parser nor claims general Markdown edit parity.
@Suite("Markdown pre-edit window feasibility", .serialized)
@MainActor
struct MarkdownPreEditWindowProbeTests {
    private static let documentBytes = 1_048_576
    private static let windowLimit = 65536

    private struct Case {
        let name: String
        let island: String
        let needle: String
        let replacement: String
        let expectedCandidate: Bool
        var atStart = false
    }

    private enum Decision {
        case candidate(NSRange)
        case refused(String)
    }

    private struct Capture: Equatable, Comparable {
        let name: String
        let location: Int
        let length: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.location != rhs.location {
                return lhs.location < rhs.location
            }
            if lhs.length != rhs.length {
                return lhs.length < rhs.length
            }
            return lhs.name < rhs.name
        }
    }

    private struct Comparison {
        let edited: String
        let excerpt: String
        let window: NSRange
        let visible: NSRange
        let name: String
    }

    @Test(.timeLimit(.minutes(3)))
    func preEditPlainParagraphWindowRefusesStructuralEdits() throws {
        let registry = GrammarRegistry()
        let root = try #require(registry.configuration(for: "markdown"))
        let inline = try #require(registry.configuration(for: "markdown_inline"))
        for specimen in Self.cases {
            let original = fixture(specimen)
            #expect(original.utf8.count == Self.documentBytes)
            let source = original as NSString
            let edit = source.range(of: specimen.needle)
            try #require(edit.location != NSNotFound)
            let before = try layer(original, root: root, registry: registry)
            let oldRoot = try #require(before.snapshot()?.rootSnapshot.tree.rootNode)
            let start = max(0, edit.location - 64)
            let oldVisible = NSRange(location: start, length: min(source.length - start, edit.length + 192))
            let decision = try selectWindow(source: source, edit: edit, replacement: specimen.replacement,
                                            visible: oldVisible, root: oldRoot)
            guard case let .candidate(window) = decision else {
                if case let .refused(reason) = decision {
                    print("PREEDIT_WINDOW case=\(specimen.name) outcome=refused reason=\(reason)")
                }
                #expect(!specimen.expectedCandidate, "\(specimen.name) refused a candidate")
                continue
            }
            #expect(specimen.expectedCandidate, "\(specimen.name) admitted structural context")
            guard specimen.expectedCandidate else { continue }

            let edited = source.replacingCharacters(in: edit, with: specimen.replacement)
            let visible = NSRange(
                location: start,
                length: min((edited as NSString).length - start, (specimen.replacement as NSString).length + 192)
            )
            let whole = try layer(edited, root: root, registry: registry)
            let excerpt = (edited as NSString).substring(with: window)
            let local = try layer(excerpt, root: root, registry: registry)
            try compare(whole: whole, local: local, inline: inline,
                        context: Comparison(edited: edited, excerpt: excerpt, window: window,
                                            visible: visible, name: specimen.name))
        }
    }

    /// Only interior alphanumeric substitutions in a punctuation-free,
    /// single-line paragraph are candidates. A pre-edit root tree supplies the
    /// visible root children; the post-edit full tree is not consulted here.
    private func selectWindow(
        source: NSString, edit: NSRange, replacement: String, visible: NSRange, root: Node
    ) throws -> Decision {
        let old = source.substring(with: edit)
        let word = CharacterSet.alphanumerics
        guard !old.isEmpty, !replacement.isEmpty,
              old.unicodeScalars.allSatisfy(word.contains),
              replacement.unicodeScalars.allSatisfy(word.contains)
        else { return .refused("structural-or-empty-edit") }
        let editedNodes = try rootChildren(overlapping: edit, in: root)
        guard editedNodes.count == 1, let section = editedNodes.first,
              section.nodeType == "section", !section.hasError
        else { return .refused("not-one-clean-section") }
        let paragraphs = (0 ..< section.childCount).compactMap { section.child(at: $0) }
            .filter { $0.nodeType == "paragraph" && NSIntersectionRange($0.range, edit).length > 0 }
        guard paragraphs.count == 1, let node = paragraphs.first, !node.hasError,
              edit.location > node.range.location,
              NSMaxRange(edit) < NSMaxRange(node.range)
        else { return .refused("not-interior-plain-paragraph") }
        guard node.range.length <= Self.windowLimit else { return .refused("paragraph-unbounded") }
        let paragraph = source.substring(with: node.range)
        let content = paragraph.hasSuffix("\n") ? String(paragraph.dropLast()) : paragraph
        guard content.unicodeScalars.allSatisfy({ word.contains($0) || $0 == " " || $0 == "\t" })
        else { return .refused("paragraph-has-structure") }
        let selected = try rootChildren(overlapping: visible, in: root)
        guard !selected.isEmpty else { return .refused("no-visible-root") }
        let lower = selected.map(\.range.location).min() ?? 0
        let upper = selected.map { NSMaxRange($0.range) }.max() ?? 0
        let delta = (replacement as NSString).length - edit.length
        let length = upper - lower + delta
        guard lower <= edit.location, NSMaxRange(edit) <= upper,
              length > 0, length <= Self.windowLimit,
              lower >= 0, lower + length <= source.length + delta
        else { return .refused("window-unbounded-or-incomplete") }
        return .candidate(NSRange(location: lower, length: length))
    }

    private func compare(
        whole: LanguageLayer, local: LanguageLayer, inline: LanguageConfiguration, context: Comparison
    ) throws {
        let full = try #require(whole.snapshot())
        let slice = try #require(local.snapshot())
        let localVisible = NSRange(location: context.visible.location - context.window.location,
                                   length: context.visible.length)
        let rootFull = try captures(full.rootSnapshot.highlights(
            in: context.visible, provider: context.edited.predicateTextProvider
        ), offset: 0, clip: context.visible)
        let rootLocal = try captures(slice.rootSnapshot.highlights(in: localVisible,
                                                                   provider: context.excerpt.predicateTextProvider),
                                     offset: context.window.location, clip: context.visible)
        let inlineFull = try inlineCaptures(full, query: inline.queries[.highlights],
                                            region: context.visible, offset: 0, clip: context.visible)
        let inlineLocal = try inlineCaptures(slice, query: inline.queries[.highlights],
                                             region: localVisible, offset: context.window.location,
                                             clip: context.visible)
        let combinedFull = try captures(full.highlights(
            in: context.visible, provider: context.edited.predicateTextProvider
        ), offset: 0, clip: context.visible)
        let combinedLocal = try captures(slice.highlights(
            in: localVisible, provider: context.excerpt.predicateTextProvider
        ), offset: context.window.location, clip: context.visible)
        #expect(rootFull == rootLocal, "\(context.name) root captures differ")
        #expect(inlineFull == inlineLocal, "\(context.name) inline captures differ")
        #expect(combinedFull == combinedLocal, "\(context.name) combined captures differ")
        #expect(!rootFull.isEmpty || !inlineFull.isEmpty || !combinedFull.isEmpty,
                "\(context.name) compared no visible captures")
        print("PREEDIT_WINDOW case=\(context.name) outcome=matched windowUTF16=\(context.window.length) " +
            "captures=\(rootFull.count)/\(inlineFull.count)/\(combinedFull.count)")
    }

    private func inlineCaptures(
        _ snapshot: LanguageLayerTreeSnapshot, query: Query?, region: NSRange,
        offset: Int, clip: NSRange
    ) throws -> [Capture] {
        let tree = try #require(snapshot.sublayerSnapshots.first { $0.rootSnapshot.data.name == "MarkdownInline" }?
            .rootSnapshot.tree)
        let query = try #require(query)
        let node = try #require(tree.rootNode)
        let cursor = query.execute(node: node, in: tree)
        cursor.setRange(region)
        return captures(cursor.highlights(), offset: offset, clip: clip)
    }

    private func captures(_ ranges: [NamedRange], offset: Int, clip: NSRange) -> [Capture] {
        ranges.compactMap { capture in
            let global = NSRange(location: capture.range.location + offset, length: capture.range.length)
            let visible = NSIntersectionRange(global, clip)
            guard visible.length > 0 else { return nil }
            return Capture(name: capture.name, location: visible.location, length: visible.length)
        }.sorted()
    }

    private func rootChildren(overlapping region: NSRange, in root: Node) throws -> [Node] {
        var lower = 0
        var upper = root.childCount
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let child = try #require(root.child(at: middle))
            if NSMaxRange(child.range) <= region.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        var result: [Node] = []
        var index = lower
        while index < root.childCount {
            let child = try #require(root.child(at: index))
            if child.range.location >= NSMaxRange(region) {
                break
            }
            if NSIntersectionRange(child.range, region).length > 0 {
                result.append(child)
            }
            index += 1
        }
        return result
    }

    private func layer(_ text: String, root: LanguageConfiguration, registry: GrammarRegistry) throws -> LanguageLayer {
        let result = try LanguageLayer(languageConfig: root,
                                       configuration: .init(languageProvider: registry.languageProvider))
        _ = result.replaceContent(with: text)
        return result
    }

    private func fixture(_ specimen: Case) -> String {
        let stable = "# Stable\n\nPlain content between independent headings.\n\n"
        let prefix = specimen.atStart ? "" : String(repeating: stable, count: 440_000 / stable.utf8.count)
        let base = prefix + specimen.island
        let remainder = Self.documentBytes - base.utf8.count
        precondition(remainder > 0)
        return base + String(repeating: stable, count: remainder / stable.utf8.count)
            + String(repeating: "x", count: remainder % stable.utf8.count)
    }
}

private extension MarkdownPreEditWindowProbeTests {
    private static let cases: [Case] = [
        .init(name: "paragraph-middle",
              island: "# Probe\n\nPlain alphatarget content with context\n\n**bold** tail.\n\n",
              needle: "alphatarget", replacement: "betaword", expectedCandidate: true),
        .init(name: "paragraph-start",
              island: "# Probe\n\nPlain alphatarget content with context\n\n**bold** tail.\n\n",
              needle: "alphatarget", replacement: "betaword", expectedCandidate: true, atStart: true),
        .init(name: "paragraph-unicode",
              island: "# Probe\n\nPlain cafétarget content with context\n\n**bold** tail.\n\n",
              needle: "cafétarget", replacement: "漢字word", expectedCandidate: true),
        .init(name: "fence-opener",
              island: "# Probe\n\n```js\nconst target = 'code';\n```\n\n**bold** tail.\n\n",
              needle: "```js", replacement: "``js", expectedCandidate: false),
        .init(name: "list-marker",
              island: "# Probe\n\n- LIST_MARKER with **bold**\n  - nested `code`\n\nEnd.\n\n",
              needle: "- LIST_MARKER", replacement: "  LIST_MARKER", expectedCandidate: false),
        .init(name: "heading-word",
              island: "# Probe\n\nPlain content with context\n\n**bold** tail.\n\n",
              needle: "Probe", replacement: "Other", expectedCandidate: false),
        .init(name: "markup-paragraph",
              island: "# Probe\n\nPlain alphatarget with **bold** context\n\n",
              needle: "alphatarget", replacement: "betaword", expectedCandidate: false),
        .init(name: "long-paragraph",
              island: "# Probe\n\n" + String(repeating: "a", count: 70000) + " alphatarget context\n\n",
              needle: "alphatarget", replacement: "betaword", expectedCandidate: false),
    ]
}

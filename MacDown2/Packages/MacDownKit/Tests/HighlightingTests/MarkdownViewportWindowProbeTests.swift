import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

/// A parser-only feasibility probe for issue #18. The fresh full-document parse
/// is an oracle, not an implementation strategy: it tells us whether a root
/// boundary could be parsed independently after a particular edit. No editor,
/// Neon highlighter, or AppKit view is created here.
@Suite("Markdown viewport window feasibility", .serialized)
@MainActor
struct MarkdownViewportWindowProbeTests {
    private static let documentBytes = 1_048_576
    private static let diagnosticWindowLimit = 65536 // Probe stop rule, not a product threshold.

    private struct Case {
        let name: String
        let island: String
        let needle: String
        let replacement: String
        var atStart = false
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

    private enum Outcome: String {
        case matching
        case unboundedWindow
        case rootMismatch
        case inlineMismatch
        case combinedMismatch
    }

    private struct ProbeContext {
        let name: String
        let edited: String
        let excerpt: String
        let visible: NSRange
        let window: NSRange
        let rootChildren: Int
        let touched: Int
        let oracleDuration: Duration
        let boundaryDuration: Duration
        let windowStart: ContinuousClock.Instant
    }

    @Test(.timeLimit(.minutes(3)))
    func oracleRootWindowsAndInlineCapturesAfterEdits() throws {
        let registry = GrammarRegistry()
        let root = try #require(registry.configuration(for: "markdown"))
        let inline = try #require(registry.configuration(for: "markdown_inline"))
        let languageProvider = registry.languageProvider

        for specimen in Self.cases {
            let outcome = try probe(specimen, root: root, inline: inline, languageProvider: languageProvider)
            // The structural fence edit is a durable negative control. If the
            // grammar starts producing a bounded region, re-evaluate the design.
            let expected: Outcome = specimen.name == "fence-opener" ? .unboundedWindow : .matching
            #expect(outcome == expected, "oracle window result for \(specimen.name)")
        }
    }

    private func probe(
        _ specimen: Case,
        root: LanguageConfiguration,
        inline: LanguageConfiguration,
        languageProvider: @escaping LanguageLayer.LanguageProvider
    ) throws -> Outcome {
        let original = fixture(specimen)
        #expect(original.utf8.count == Self.documentBytes)
        let match = (original as NSString).range(of: specimen.needle)
        try #require(match.location != NSNotFound)
        let edited = (original as NSString).replacingCharacters(in: match, with: specimen.replacement)
        let changed = NSRange(location: match.location, length: (specimen.replacement as NSString).length)
        let start = max(0, changed.location - 64)
        let visible = NSRange(location: start, length: min((edited as NSString).length - start, changed.length + 192))

        let oracleStart = ContinuousClock().now
        let whole = try layer(edited, root: root, languageProvider: languageProvider)
        let oracleDuration = ContinuousClock().now - oracleStart
        let rootNode = try #require(whole.snapshot()?.rootSnapshot.tree.rootNode)
        let boundaryStart = ContinuousClock().now
        let touched = try rootChildren(overlapping: visible, in: rootNode)
        let boundaryDuration = ContinuousClock().now - boundaryStart
        try #require(!touched.isEmpty)
        let lower = touched.map(\.range.location).min() ?? 0
        let upper = touched.map { NSMaxRange($0.range) }.max() ?? 0
        let window = NSRange(location: lower, length: upper - lower)
        let sourceUnits = (edited as NSString).length

        guard window.length <= Self.diagnosticWindowLimit,
              window.location >= 0,
              NSMaxRange(window) <= sourceUnits else {
            print("VIEWPORT_PROBE case=\(specimen.name) outcome=unboundedWindow " +
                "windowUTF16=\(window.length) documentUTF16=\(sourceUnits) " +
                "rootChildren=\(rootNode.childCount) touched=\(touched.count) " +
                "oracle=\(oracleDuration) boundary=\(boundaryDuration)")
            return .unboundedWindow
        }

        let windowStart = ContinuousClock().now
        let excerpt = (edited as NSString).substring(with: window)
        let slice = try layer(excerpt, root: root, languageProvider: languageProvider)
        let context = ProbeContext(
            name: specimen.name, edited: edited, excerpt: excerpt, visible: visible,
            window: window, rootChildren: rootNode.childCount, touched: touched.count,
            oracleDuration: oracleDuration, boundaryDuration: boundaryDuration, windowStart: windowStart
        )
        return try compare(whole: whole, slice: slice, inlineQuery: inline.queries[.highlights], context: context)
    }

    private func compare(
        whole: LanguageLayer,
        slice: LanguageLayer,
        inlineQuery: Query?,
        context: ProbeContext
    ) throws -> Outcome {
        let full = try #require(whole.snapshot())
        let local = try #require(slice.snapshot())
        let visible = context.visible
        let localVisible = NSRange(location: visible.location - context.window.location, length: visible.length)
        let rootFull = try normalized(full.rootSnapshot.highlights(
            in: visible, provider: context.edited.predicateTextProvider
        ), offset: 0, clippedTo: visible)
        let rootLocal = try normalized(local.rootSnapshot.highlights(
            in: localVisible, provider: context.excerpt.predicateTextProvider
        ), offset: context.window.location, clippedTo: visible)
        let inlineFull = try inlineCaptures(of: full, query: inlineQuery, region: visible, offset: 0, clip: visible)
        let inlineLocal = try inlineCaptures(of: local, query: inlineQuery, region: localVisible,
                                             offset: context.window.location, clip: visible)
        let combinedFull = try normalized(full.highlights(
            in: visible, provider: context.edited.predicateTextProvider
        ), offset: 0, clippedTo: visible)
        let combinedLocal = try normalized(local.highlights(
            in: localVisible, provider: context.excerpt.predicateTextProvider
        ), offset: context.window.location, clippedTo: visible)
        let outcome: Outcome = if rootFull != rootLocal {
            .rootMismatch
        } else if inlineFull != inlineLocal {
            .inlineMismatch
        } else if combinedFull != combinedLocal {
            .combinedMismatch
        } else {
            .matching
        }
        let duration = ContinuousClock().now - context.windowStart
        print("VIEWPORT_PROBE case=\(context.name) outcome=\(outcome.rawValue) " +
            "windowUTF16=\(context.window.length) documentUTF16=\((context.edited as NSString).length) " +
            "rootChildren=\(context.rootChildren) touched=\(context.touched) " +
            "rootCaptures=\(rootFull.count)/\(rootLocal.count) " +
            "inlineCaptures=\(inlineFull.count)/\(inlineLocal.count) " +
            "combinedCaptures=\(combinedFull.count)/\(combinedLocal.count) " +
            "oracle=\(context.oracleDuration) boundary=\(context.boundaryDuration) window=\(duration)")
        reportDifference("ROOT", name: context.name, full: rootFull, local: rootLocal)
        reportDifference("INLINE", name: context.name, full: inlineFull, local: inlineLocal)
        reportDifference("COMBINED", name: context.name, full: combinedFull, local: combinedLocal)
        return outcome
    }

    private func reportDifference(_ kind: String, name: String, full: [Capture], local: [Capture]) {
        guard full != local else { return }
        let shared = min(full.count, local.count)
        let first = (0 ..< shared).first { full[$0] != local[$0] } ?? shared
        let expected = first < full.count ? String(describing: full[first]) : "<end>"
        let actual = first < local.count ? String(describing: local[first]) : "<end>"
        print("VIEWPORT_PROBE_\(kind)_DIFF case=\(name) index=\(first) " +
            "fullCount=\(full.count) sliceCount=\(local.count) full=\(expected) slice=\(actual)")
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

    /// A full root tree is available only to the oracle. Search its ordered
    /// children without walking all ~20,000 sections on each edit.
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
        var touched: [Node] = []
        var index = lower
        while index < root.childCount {
            let child = try #require(root.child(at: index))
            if child.range.location >= NSMaxRange(region) {
                break
            }
            if NSIntersectionRange(child.range, region).length > 0 {
                touched.append(child)
            }
            index += 1
        }
        return touched
    }

    private func layer(
        _ text: String,
        root: LanguageConfiguration,
        languageProvider: @escaping LanguageLayer.LanguageProvider
    ) throws -> LanguageLayer {
        let result = try LanguageLayer(languageConfig: root, configuration: .init(languageProvider: languageProvider))
        _ = result.replaceContent(with: text)
        return result
    }

    private func inlineCaptures(
        of snapshot: LanguageLayerTreeSnapshot,
        query: Query?,
        region: NSRange,
        offset: Int,
        clip: NSRange
    ) throws -> [Capture] {
        let tree = try #require(snapshot.sublayerSnapshots.first { $0.rootSnapshot.data.name == "MarkdownInline" }?
            .rootSnapshot.tree)
        let query = try #require(query)
        let node = try #require(tree.rootNode)
        let cursor = query.execute(node: node, in: tree)
        cursor.setRange(region)
        return normalized(cursor.highlights(), offset: offset, clippedTo: clip)
    }

    private func normalized(_ captures: [NamedRange], offset: Int, clippedTo clip: NSRange) -> [Capture] {
        captures.compactMap { capture in
            let global = NSRange(location: capture.range.location + offset, length: capture.range.length)
            let visible = NSIntersectionRange(global, clip)
            guard visible.length > 0 else { return nil }
            return Capture(name: capture.name, location: visible.location, length: visible.length)
        }.sorted()
    }
}

private extension MarkdownViewportWindowProbeTests {
    private static let cases: [Case] = [
        .init(
            name: "fence-content",
            island: "# Probe\n\n```js\nconst target = 'FENCE_TEXT';\n```\n\n**bold** tail.\n\n",
            needle: "FENCE_TEXT",
            replacement: "FENCE_EDIT"
        ),
        .init(name: "fence-opener", island: "# Probe\n\n```js\nconst target = 'code';\n```\n\n**bold** tail.\n\n",
              needle: "```js", replacement: "``js"),
        .init(name: "nested-list", island: "# Probe\n\n- outer **bold**\n  - LIST_TARGET with `code`\n\nEnd.\n\n",
              needle: "LIST_TARGET", replacement: "list edit"),
        .init(name: "list-marker", island: "# Probe\n\n- LIST_MARKER with **bold**\n  - nested `code`\n\nEnd.\n\n",
              needle: "- LIST_MARKER", replacement: "  LIST_MARKER"),
        .init(
            name: "quote-marker",
            island: "# Probe\n\n> QUOTE_TARGET with **bold**\n> second `code` line\n\nEnd.\n\n",
            needle: "> QUOTE_TARGET",
            replacement: "QUOTE_TARGET"
        ),
        .init(name: "html-block", island: "# Probe\n\n<div>HTML_TARGET **literal**</div>\n\nAfter `code`.\n\n",
              needle: "HTML_TARGET", replacement: "HTML_EDIT"),
        .init(
            name: "html-delimiter",
            island: "# Probe\n\n<div>HTML_TAG with **literal**</div>\n\nAfter `code`.\n\n",
            needle: "<div>",
            replacement: "<div"
        ),
        .init(
            name: "frontmatter",
            island: "---\ntitle: FRONT_TARGET\ntags: [café, 漢字]\n---\n\n# Probe\n\n**bold** text.\n\n",
            needle: "FRONT_TARGET",
            replacement: "Front edit",
            atStart: true
        ),
        .init(
            name: "frontmatter-delimiter",
            island: "---\ntitle: Front\ntags: [café, 漢字]\n---\n\n# Probe\n\n**bold** text.\n\n",
            needle: "---",
            replacement: "--",
            atStart: true
        ),
        .init(
            name: "mixed-endings",
            island: "# Probe\r\n\r\n- MIXED_TARGET **bold**\r> quoted `code`\r\n\r\nEnd.\n\n",
            needle: "MIXED_TARGET",
            replacement: "Mixed edit"
        ),
        .init(
            name: "mixed-ending-boundary",
            island: "# Probe\r\n\r\n- MIXED_BOUNDARY **bold**\r> quoted `code`\r\n\r\nEnd.\n\n",
            needle: "\r> quoted",
            replacement: "\r\n> quoted"
        ),
        .init(name: "unicode-inline", island: "# Probe\n\n*café é 👩🏽‍💻 UNICODE_TARGET* and **bold**.\n\n",
              needle: "UNICODE_TARGET", replacement: "漢字 😀"),
    ]
}

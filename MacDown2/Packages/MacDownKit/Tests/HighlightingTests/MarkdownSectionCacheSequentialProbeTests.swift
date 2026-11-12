import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

private enum SectionProbeLimits {
    static let windowLimit = 65536
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

private struct Captures: Equatable {
    let root: [Capture]
    let inline: [Capture]
    let combined: [Capture]

    var isEmpty: Bool {
        root.isEmpty && inline.isEmpty && combined.isEmpty
    }
}

private struct Section {
    let node: Node
    let layer: LanguageLayer
    let content: String
    var offset: Int

    var globalRange: NSRange {
        NSRange(location: node.range.location + offset, length: node.range.length)
    }
}

private struct Window {
    let old: NSRange
    let new: NSRange
    let firstSection: Int
    let lastSection: Int
}

private struct Step {
    let name: String
    let source: String
    let visible: NSRange
    let candidate: Captures
    let windowLength: Int
    let duration: Duration
}

private struct EditSpec {
    let name: String
    let needle: String
    let replacement: String
}

private struct ProbeLanguages {
    let root: LanguageConfiguration
    let inline: LanguageConfiguration
    let registry: GrammarRegistry
}

@MainActor
private struct SectionCache {
    var sections: [Section]
    var shifts: SectionShifts

    init(source: String, layer: LanguageLayer) throws {
        let snapshot = try #require(layer.snapshot())
        let root = try #require(snapshot.rootSnapshot.tree.rootNode)
        sections = try (0 ..< root.childCount).map { index in
            let node = try #require(root.child(at: index))
            return Section(node: node, layer: layer, content: source, offset: 0)
        }
        #expect(!sections.isEmpty)
        shifts = SectionShifts(sectionCount: sections.count)
    }

    /// Uses only the cached pre-edit sections and the old source. Return
    /// nil on structural or unbounded edits; no full tree is consulted.
    func select(source: NSString, edit: NSRange, replacement: String, visible: NSRange) -> Window? {
        let word = CharacterSet.alphanumerics
        guard edit.location >= 0, NSMaxRange(edit) <= source.length,
              !replacement.isEmpty, edit.length > 0
        else { return nil }
        let old = source.substring(with: edit)
        guard old.unicodeScalars.allSatisfy(word.contains),
              replacement.unicodeScalars.allSatisfy(word.contains)
        else { return nil }

        guard let editIndex = firstIndex(overlapping: edit) else { return nil }
        let entry = resolvedSection(at: editIndex)
        let node = entry.node
        let localEdit = NSRange(location: edit.location - entry.offset, length: edit.length)
        guard node.nodeType == "section", !node.hasError else { return nil }
        let paragraphs = (0 ..< node.childCount).compactMap { node.child(at: $0) }
            .filter { $0.nodeType == "paragraph" && NSIntersectionRange($0.range, localEdit).length > 0 }
        guard paragraphs.count == 1, let paragraph = paragraphs.first, !paragraph.hasError,
              localEdit.location > paragraph.range.location,
              NSMaxRange(localEdit) < NSMaxRange(paragraph.range),
              paragraph.range.length <= SectionProbeLimits.windowLimit
        else { return nil }
        let paragraphText = (entry.content as NSString).substring(with: paragraph.range)
        let body = paragraphText.hasSuffix("\n") ? String(paragraphText.dropLast()) : paragraphText
        guard body.unicodeScalars.allSatisfy({ word.contains($0) || $0 == " " || $0 == "\t" })
        else { return nil }

        guard let firstVisible = firstIndex(overlapping: visible) else { return nil }
        var lastVisible = firstVisible
        while lastVisible + 1 < sections.count,
              globalRange(at: lastVisible + 1).location < NSMaxRange(visible) {
            lastVisible += 1
        }
        let first = min(editIndex, firstVisible)
        let last = max(editIndex, lastVisible)
        let lower = globalRange(at: first).location
        let upper = NSMaxRange(globalRange(at: last))
        let delta = (replacement as NSString).length - edit.length
        let newLength = upper - lower + delta
        guard lower <= edit.location, NSMaxRange(edit) <= upper,
              newLength > 0, newLength <= SectionProbeLimits.windowLimit,
              lower >= 0, lower + newLength <= source.length + delta
        else { return nil }
        return Window(old: NSRange(location: lower, length: upper - lower),
                      new: NSRange(location: lower, length: newLength),
                      firstSection: first, lastSection: last)
    }

    mutating func replace(_ window: Window, with layer: LanguageLayer, content: String,
                          delta: Int) throws {
        let snapshot = try #require(layer.snapshot())
        let root = try #require(snapshot.rootSnapshot.tree.rootNode)
        let expectedCount = window.lastSection - window.firstSection + 1
        try #require(root.childCount == expectedCount,
                     "plain-word edit changed the number of root sections")
        let replacements = try (0 ..< root.childCount).map { index in
            let node = try #require(root.child(at: index))
            let sectionIndex = window.firstSection + index
            return Section(node: node, layer: layer, content: content,
                           offset: window.new.location - shifts.displacement(at: sectionIndex))
        }
        sections.replaceSubrange(window.firstSection ... window.lastSection, with: replacements)
        shifts.shift(after: window.lastSection, by: delta)
    }

    func visibleSections(_ visible: NSRange) -> [Section] {
        guard let first = firstIndex(overlapping: visible) else { return [] }
        var result: [Section] = []
        var index = first
        while index < sections.count, globalRange(at: index).location < NSMaxRange(visible) {
            let section = resolvedSection(at: index)
            if NSIntersectionRange(section.globalRange, visible).length > 0 {
                result.append(section)
            }
            index += 1
        }
        return result
    }

    private func resolvedSection(at index: Int) -> Section {
        var section = sections[index]
        section.offset += shifts.displacement(at: index)
        return section
    }

    private func globalRange(at index: Int) -> NSRange {
        resolvedSection(at: index).globalRange
    }

    private func firstIndex(overlapping region: NSRange) -> Int? {
        var lower = 0
        var upper = sections.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(globalRange(at: middle)) <= region.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < sections.count,
              NSIntersectionRange(globalRange(at: lower), region).length > 0
        else { return nil }
        return lower
    }
}

/// Parser-only follow-up to the pre-edit window probe. A cache of root
/// sections survives repeated edits and viewport moves without a full reparse.
/// Full-document parses are constructed only after the candidate sequence,
/// as independent capture oracles. This does not change the product path.
@Suite("Markdown sequential section cache feasibility", .serialized)
@MainActor
struct MarkdownSectionCacheSequentialProbeTests {
    private static let documentBytes = 1_048_576

    @Test(.timeLimit(.minutes(3)))
    func consecutiveEditsAndViewportMoveKeepExactVisibleCaptures() throws {
        let registry = GrammarRegistry()
        let root = try #require(registry.configuration(for: "markdown"))
        let inline = try #require(registry.configuration(for: "markdown_inline"))
        let languages = ProbeLanguages(root: root, inline: inline, registry: registry)
        let original = Self.fixture()
        #expect(original.utf8.count == Self.documentBytes)
        let initial = try layer(original, root: root, registry: registry)
        var cache = try SectionCache(source: original, layer: initial)
        var source = original
        var steps: [Step] = []

        let initialHeading = (original as NSString).range(of: "Probe Two")
        try #require(initialHeading.location != NSNotFound)
        #expect(cache.select(source: original as NSString, edit: initialHeading,
                             replacement: "Other", visible: initialHeading) == nil,
                "heading edit was admitted")

        let edits = [
            EditSpec(name: "first", needle: "alphatarget", replacement: "betawordlonger"),
            EditSpec(name: "second", needle: "gammatarget", replacement: "deltaword"),
        ]
        let originalSecond = (original as NSString).range(of: "gammatarget").location
        for edit in edits {
            try steps.append(applyEdit(edit, source: &source, cache: &cache, languages: languages))
        }

        #expect(steps[1].visible.location > steps[0].visible.location, "viewport did not move")
        let firstDelta = (edits[0].replacement as NSString).length - (edits[0].needle as NSString).length
        let shiftedSecond = (steps[0].source as NSString).range(of: "gammatarget").location
        #expect(shiftedSecond == originalSecond + firstDelta, "later section offset did not shift")
        try applyRevisions(source: &source, cache: &cache, languages: languages, steps: &steps)
        #expect(steps.count == 14, "repeated edits did not all enter the bounded window")

        // Return to the first edited section after a second section and the
        // viewport have moved. This checks that its cached local tree remains
        // usable after another edit without reparsing the whole source.
        let revisitStart = ContinuousClock().now
        let revisit = try captures(cache.visibleSections(steps[0].visible),
                                   visible: steps[0].visible, inline: inline)
        let revisitDuration = ContinuousClock().now - revisitStart
        #expect(!revisit.isEmpty)
        steps.append(Step(name: "revisit-first", source: source, visible: steps[0].visible,
                          candidate: revisit, windowLength: 0, duration: revisitDuration))
        print("SECTION_CACHE step=revisit-first captures=\(revisit.root.count)/" +
            "\(revisit.inline.count)/\(revisit.combined.count) candidate=\(revisitDuration)")

        // No full post-edit parse was made while applying any candidate.
        // Construct independent oracles only now, after the cache has
        // survived repeated edits and viewport movement.
        for step in steps {
            try compareWithFullOracle(step, languages: languages)
        }
    }

    private func applyRevisions(
        source: inout String, cache: inout SectionCache,
        languages: ProbeLanguages, steps: inout [Step]
    ) throws {
        var firstWord = "betawordlonger"
        var secondWord = "deltaword"
        for revision in 0 ..< 12 {
            let isFirst = revision.isMultiple(of: 2)
            let previous = isFirst ? firstWord : secondWord
            let next = (isFirst ? "alphaprobe" : "gammaprobe") + String(repeating: isFirst ? "q" : "z",
                                                                        count: revision + 1)
            try steps.append(applyEdit(
                EditSpec(name: "revision-\(revision)", needle: previous, replacement: next),
                source: &source, cache: &cache, languages: languages
            ))
            if isFirst {
                firstWord = next
            } else {
                secondWord = next
            }
        }
    }

    private func applyEdit(
        _ editSpec: EditSpec, source: inout String, cache: inout SectionCache,
        languages: ProbeLanguages
    ) throws -> Step {
        let old = source as NSString
        let edit = old.range(of: editSpec.needle)
        try #require(edit.location != NSNotFound)
        let visibleStart = max(0, edit.location - 64)
        let visibleOld = NSRange(location: visibleStart,
                                 length: min(old.length - visibleStart, edit.length + 192))
        let start = ContinuousClock().now
        let window = try #require(cache.select(source: old, edit: edit, replacement: editSpec.replacement,
                                               visible: visibleOld), "\(editSpec.name) refused a plain paragraph")
        source = old.replacingCharacters(in: edit, with: editSpec.replacement)
        let newContent = (source as NSString).substring(with: window.new)
        let localLayer = try layer(newContent, root: languages.root, registry: languages.registry)
        try cache.replace(window, with: localLayer, content: newContent,
                          delta: (editSpec.replacement as NSString).length - edit.length)
        let visible = NSRange(location: visibleStart,
                              length: min((source as NSString).length - visibleStart,
                                          (editSpec.replacement as NSString).length + 192))
        let candidate = try captures(cache.visibleSections(visible), visible: visible, inline: languages.inline)
        let duration = ContinuousClock().now - start
        #expect(!candidate.isEmpty, "\(editSpec.name) yielded no visible captures")
        #expect(window.new.length <= SectionProbeLimits.windowLimit)
        print("SECTION_CACHE step=\(editSpec.name) windowUTF16=\(window.new.length) " +
            "captures=\(candidate.root.count)/\(candidate.inline.count)/\(candidate.combined.count) " +
            "candidate=\(duration)")
        return Step(name: editSpec.name, source: source, visible: visible,
                    candidate: candidate, windowLength: window.new.length, duration: duration)
    }

    private func compareWithFullOracle(_ step: Step, languages: ProbeLanguages) throws {
        let whole = try layer(step.source, root: languages.root, registry: languages.registry)
        let snapshot = try #require(whole.snapshot())
        let rootNode = try #require(snapshot.rootSnapshot.tree.rootNode)
        let wholeSection = Section(node: rootNode, layer: whole, content: step.source,
                                   offset: 0)
        let oracle = try captures([wholeSection], visible: step.visible, inline: languages.inline)
        #expect(step.candidate.root == oracle.root, "\(step.name) root captures differ")
        #expect(step.candidate.inline == oracle.inline, "\(step.name) inline captures differ")
        #expect(step.candidate.combined == oracle.combined, "\(step.name) combined captures differ")
        print("SECTION_CACHE_ORACLE step=\(step.name) outcome=matched " +
            "windowUTF16=\(step.windowLength) candidate=\(step.duration)")
    }

    private func captures(_ sections: [Section], visible: NSRange,
                          inline: LanguageConfiguration) throws -> Captures {
        var root: [Capture] = []
        var inlineRanges: [Capture] = []
        var combined: [Capture] = []
        let inlineQuery = try #require(inline.queries[.highlights])
        for section in sections {
            let clip = NSIntersectionRange(visible, section.globalRange)
            guard clip.length > 0 else { continue }
            let local = NSRange(location: clip.location - section.offset, length: clip.length)
            let snapshot = try #require(section.layer.snapshot())
            let provider = section.content.predicateTextProvider
            try root += Self.capture(snapshot.rootSnapshot.highlights(in: local, provider: provider),
                                     offset: section.offset, clip: clip)
            let inlineTree = try #require(snapshot.sublayerSnapshots.first {
                $0.rootSnapshot.data.name == "MarkdownInline"
            }?.rootSnapshot.tree)
            let inlineNode = try #require(inlineTree.rootNode)
            let cursor = inlineQuery.execute(node: inlineNode, in: inlineTree)
            cursor.setRange(local)
            inlineRanges += Self.capture(cursor.highlights(), offset: section.offset, clip: clip)
            try combined += Self.capture(snapshot.highlights(in: local, provider: provider),
                                         offset: section.offset, clip: clip)
        }
        return Captures(root: root.sorted(), inline: inlineRanges.sorted(), combined: combined.sorted())
    }

    private static func capture(_ ranges: [NamedRange], offset: Int, clip: NSRange) -> [Capture] {
        ranges.compactMap { range in
            let global = NSRange(location: range.range.location + offset, length: range.range.length)
            let clipped = NSIntersectionRange(global, clip)
            guard clipped.length > 0 else { return nil }
            return Capture(name: range.name, location: clipped.location, length: clipped.length)
        }
    }

    private func layer(_ text: String, root: LanguageConfiguration,
                       registry: GrammarRegistry) throws -> LanguageLayer {
        let result = try LanguageLayer(languageConfig: root,
                                       configuration: .init(languageProvider: registry.languageProvider))
        _ = result.replaceContent(with: text)
        return result
    }

    private static func fixture() -> String {
        let stable = "# Stable\n\nPlain content between independent headings.\n\n"
        let prefix = String(repeating: stable, count: 440_000 / stable.utf8.count)
        let islands = "# Probe One\n\nPlain alphatarget content with context\n\n**bold** tail.\n\n" +
            "# Probe Two\n\nPlain gammatarget content with context\n\n**bold** tail.\n\n"
        let base = prefix + islands
        let remainder = documentBytes - base.utf8.count
        precondition(remainder > 0)
        return base + String(repeating: stable, count: remainder / stable.utf8.count)
            + String(repeating: "x", count: remainder % stable.utf8.count)
    }
}

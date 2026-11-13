import AppKit
import EditorCore
import Foundation
@testable import Highlighting
import Neon
import RangeState
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

private struct ProbeLanguages {
    let root: LanguageConfiguration
    let inline: LanguageConfiguration
    let registry: GrammarRegistry
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
    func inWordInsertionKeepsOneMegabyteVisibleCapturesExact() async throws {
        let registry = GrammarRegistry()
        let root = try #require(registry.configuration(for: "markdown"))
        let inline = try #require(registry.configuration(for: "markdown_inline"))
        let original = Self.fixture()
        #expect(original.utf8.count == Self.documentBytes)
        let initialSnapshot = try await Task.detached {
            try MarkdownSectionParser.snapshot(source: original, registry: registry)
        }.value
        var cache = try SectionCache(source: original, snapshot: initialSnapshot)
        let source = original as NSString
        let word = source.range(of: "alphatarget")
        try #require(word.location != NSNotFound)
        let edit = NSRange(location: word.location + 5, length: 0)
        let visible = NSRange(location: word.location - 32, length: 180)
        #expect(cache.select(source: source, edit: NSRange(location: word.location, length: 0),
                             replacement: "xyz", visible: visible) == nil)
        #expect(cache.select(source: source, edit: NSRange(location: NSMaxRange(word), length: 0),
                             replacement: "xyz", visible: visible) == nil)
        #expect(cache.select(source: source, edit: edit, replacement: "*", visible: visible) == nil)

        let selected = try #require(cache.select(source: source, edit: edit,
                                                 replacement: "xyz", visible: visible))
        let updated = source.replacingCharacters(in: edit, with: "xyz")
        let localContent = (updated as NSString).substring(with: selected.new)
        let local = try layer(localContent, root: root, registry: registry)
        try cache.replace(selected, with: #require(local.snapshot()), content: localContent, delta: 3)

        let updatedVisible = NSRange(location: visible.location, length: visible.length + 3)
        let candidate = try produced(cache, visible: updatedVisible)
        let whole = try layer(updated, root: root, registry: registry)
        let snapshot = try #require(whole.snapshot())
        let node = try #require(snapshot.rootSnapshot.tree.rootNode)
        let oracle = try captures([Section(node: node, snapshot: snapshot, content: updated, offset: 0)],
                                  visible: updatedVisible, inline: inline).combined
        #expect(!candidate.isEmpty)
        #expect(candidate == oracle)
    }

    @Test(.timeLimit(.minutes(3)))
    func consecutiveEditsAndViewportMoveKeepExactVisibleCaptures() async throws {
        let registry = GrammarRegistry()
        let root = try #require(registry.configuration(for: "markdown"))
        let inline = try #require(registry.configuration(for: "markdown_inline"))
        let languages = ProbeLanguages(root: root, inline: inline, registry: registry)
        let original = Self.fixture()
        #expect(original.utf8.count == Self.documentBytes)
        let initialSnapshot = try await Task.detached {
            try MarkdownSectionParser.snapshot(source: original, registry: registry)
        }.value
        var cache = try SectionCache(source: original, snapshot: initialSnapshot)
        var source = original
        var steps: [Step] = []

        let initialHeading = (original as NSString).range(of: "Probe Two")
        try #require(initialHeading.location != NSNotFound)
        #expect(cache.select(source: original as NSString, edit: initialHeading,
                             replacement: "Other", visible: initialHeading) == nil,
                "heading edit was admitted")
        let ordinaryWord = (original as NSString).range(of: "alphatarget")
        #expect(cache.select(source: original as NSString, edit: ordinaryWord,
                             replacement: "betawordlonger",
                             visible: NSRange(location: NSNotFound, length: 1)) == nil,
                "invalid viewport was admitted")

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
        let delta = (editSpec.replacement as NSString).length - edit.length
        let localSnapshot = try #require(localLayer.snapshot())
        #expect(throws: MarkdownSectionCache.CacheError.self) {
            try cache.replace(window, with: localSnapshot,
                              content: String(newContent.dropLast()), delta: delta)
        }
        try cache.replace(window, with: localSnapshot, content: newContent, delta: delta)
        let visible = NSRange(location: visibleStart,
                              length: min((source as NSString).length - visibleStart,
                                          (editSpec.replacement as NSString).length + 192))
        let candidate = try captures(cache.visibleSections(visible), visible: visible, inline: languages.inline)
        #expect(try produced(cache, visible: visible) == candidate.combined,
                "\(editSpec.name) production tokens differ from combined captures")
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
        let wholeSection = Section(node: rootNode, snapshot: snapshot, content: step.source,
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
            let snapshot = section.snapshot
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

    private func produced(_ cache: SectionCache, visible: NSRange) throws -> [Capture] {
        try cache.tokens(in: visible).map {
            Capture(name: $0.name, location: $0.range.location, length: $0.range.length)
        }.sorted()
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

@MainActor
extension MarkdownSectionCacheSequentialProbeTests {
    /// The mounted 1 MiB source, parser cache, TextKit 2 adapter and oracle form one lifecycle.
    @Test(.timeLimit(.minutes(3)))
    // swiftlint:disable:next function_body_length
    func realSectionCapturesPaintThroughPublicStylerAcrossEditsAndViewportMoves() async throws {
        let registry = GrammarRegistry()
        let root = try #require(registry.configuration(for: "markdown"))
        let inline = try #require(registry.configuration(for: "markdown_inline"))
        let original = Self.fixture()
        let initialSnapshot = try await Task.detached {
            try MarkdownSectionParser.snapshot(source: original, registry: registry)
        }.value
        var cache = try SectionCache(source: original, snapshot: initialSnapshot)
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let system = store.system(for: identity, initialText: original, configuration: .default)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        scroll.documentView = system.textView
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderFront(nil)
        defer {
            store.evict(identity)
            window.contentView = nil
            window.close()
        }

        let firstEdit = (original as NSString).range(of: "alphatarget")
        try #require(firstEdit.location != NSNotFound)
        let visible = NSRange(location: firstEdit.location - 32, length: 180)
        var candidate = try produced(cache, visible: visible)
        let initialCaptures = try captures(cache.visibleSections(visible), visible: visible, inline: inline)
        #expect(candidate == initialCaptures.combined)
        try #require(!candidate.isEmpty)
        let publication = CapturePublication(candidate)
        let interface = TextViewSystemInterface(textView: system.textView) { _ in
            [.foregroundColor: NSColor.systemRed]
        }
        let provider = TokenProvider(syncValue: { range in
            TokenApplication(tokens: publication.tokens, range: range, action: .replace)
        }, mainActorAsyncValue: { range in
            TokenApplication(tokens: publication.tokens, range: range, action: .replace)
        })
        let styler = TextSystemStyler(textSystem: interface, tokenProvider: provider)
        styler.invalidate(.range(visible))
        styler.validate(.range(visible))
        try expectRendered(candidate, visible: visible, in: system.textView)

        var source = original
        let edits = [
            EditSpec(name: "first", needle: "alphatarget", replacement: "betawordlonger"),
            EditSpec(name: "second", needle: "gammatarget", replacement: "deltaword"),
            EditSpec(name: "revisit-first", needle: "betawordlonger", replacement: "alphaprobe"),
            EditSpec(name: "revisit-second", needle: "deltaword", replacement: "gammaprobe"),
        ]
        for spec in edits {
            let oldSource = source as NSString
            let edit = oldSource.range(of: spec.needle)
            try #require(edit.location != NSNotFound)
            let visible = NSRange(location: edit.location - 32, length: 180)
            let selected = try #require(cache.select(source: oldSource, edit: edit,
                                                     replacement: spec.replacement, visible: visible),
                                        "\(spec.name) was not an admitted bounded edit")
            system.textView.insertText(spec.replacement, replacementRange: edit)
            source = oldSource.replacingCharacters(in: edit, with: spec.replacement)
            #expect(system.textView.string == source)
            let newContent = (source as NSString).substring(with: selected.new)
            let local = try layer(newContent, root: root, registry: registry)
            let delta = (spec.replacement as NSString).length - edit.length
            try cache.replace(selected, with: #require(local.snapshot()), content: newContent, delta: delta)
            let shiftedVisible = NSRange(location: visible.location, length: visible.length + delta)
            candidate = try produced(cache, visible: shiftedVisible)
            let independent = try captures(cache.visibleSections(shiftedVisible), visible: shiftedVisible,
                                           inline: inline)
            #expect(candidate == independent.combined)
            try #require(!candidate.isEmpty)
            publication.replace(with: candidate)
            styler.didChangeContent(in: edit, delta: delta)
            styler.invalidate(.range(shiftedVisible))
            styler.validate(.range(shiftedVisible))
            try expectRendered(candidate, visible: shiftedVisible, in: system.textView)

            let whole = try layer(source, root: root, registry: registry)
            let snapshot = try #require(whole.snapshot())
            let node = try #require(snapshot.rootSnapshot.tree.rootNode)
            let oracle = try captures([Section(node: node, snapshot: snapshot, content: source, offset: 0)],
                                      visible: shiftedVisible, inline: inline).combined
            #expect(candidate == oracle, "\(spec.name) painted stale captures")
        }
    }

    private func expectRendered(_ captures: [Capture], visible: NSRange, in textView: NSTextView) throws {
        try #require(!captures.isEmpty)
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager else {
            Issue.record("Mounted editor has no TextKit 2 layout")
            return
        }
        let origin = content.documentRange.location
        var painted = IndexSet()
        layout.enumerateRenderingAttributes(from: origin, reverse: false) { _, attributes, range in
            let location = content.offset(from: origin, to: range.location)
            let length = content.offset(from: range.location, to: range.endLocation)
            let clipped = NSIntersectionRange(NSRange(location: location, length: length), visible)
            if clipped.length > 0,
               let color = attributes[.foregroundColor] as? NSColor,
               color.isEqual(NSColor.systemRed) {
                painted.insert(integersIn: clipped.location ..< NSMaxRange(clipped))
            }
            return true
        }
        var expected = IndexSet()
        for capture in captures {
            let clipped = NSIntersectionRange(NSRange(location: capture.location, length: capture.length), visible)
            if clipped.length > 0 {
                expected.insert(integersIn: clipped.location ..< NSMaxRange(clipped))
            }
        }
        #expect(painted == expected, "Mounted TextKit 2 paint differs from the visible parser captures")
    }
}

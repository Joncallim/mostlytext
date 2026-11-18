import Foundation
import Neon
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// A conservative Markdown section cache for bounded prose edits.
/// Selection reads the old source synchronously; the caller must copy only
/// the selected window and pair the proposal with the actual storage edit.
/// Structural or uncertain edits must replace the cache from a fresh parse.
@MainActor
struct MarkdownSectionCache {
    static let windowLimit = 65536

    enum CacheError: Error {
        case snapshotUnavailable
        case sectionShapeChanged
        case windowMismatch
    }

    struct Section {
        let node: Node
        let snapshot: LanguageLayerTreeSnapshot
        let content: String
        /// Disjoint slice of `node` owned by this entry. A parent section's
        /// heading/body ends where its first nested section begins.
        let range: NSRange
        var offset: Int

        init(node: Node, snapshot: LanguageLayerTreeSnapshot, content: String,
             offset: Int, range: NSRange? = nil) {
            self.node = node
            self.snapshot = snapshot
            self.content = content
            self.offset = offset
            self.range = range ?? node.range
        }

        var globalRange: NSRange {
            NSRange(location: range.location + offset, length: range.length)
        }
    }

    struct Window {
        let old: NSRange
        let new: NSRange
        let firstSection: Int
        let lastSection: Int
    }

    private var sections: [Section]
    private var shifts: SectionShifts
    private(set) var sourceLength: Int

    /// A parse can finish on a background executor and hand over its Sendable
    /// immutable snapshot; the live parser itself never crosses actors.
    init(source: String, snapshot: LanguageLayerTreeSnapshot) throws {
        guard let root = snapshot.rootSnapshot.tree.rootNode,
              root.childCount > 0
        else { throw CacheError.snapshotUnavailable }
        var entries: [Section] = []
        entries.reserveCapacity(root.childCount)
        for index in 0 ..< root.childCount {
            guard let node = root.child(at: index) else { throw CacheError.snapshotUnavailable }
            Self.partition(node, snapshot: snapshot, source: source, into: &entries)
        }
        sections = entries
        shifts = SectionShifts(sectionCount: entries.count)
        sourceLength = (source as NSString).length
    }

    /// Admit only a text edit inside one bounded paragraph or heading slice.
    /// Keeping section count stable lets later section offsets shift in O(log n).
    func select(source: NSString, edit: NSRange, replacement: String, visible: NSRange) -> Window? {
        guard source.length == sourceLength,
              edit.location >= 0, edit.length >= 0,
              edit.location <= source.length,
              edit.length <= source.length - edit.location,
              visible.location != NSNotFound, visible.location >= 0,
              visible.length > 0, visible.location <= source.length,
              visible.length <= source.length - visible.location,
              !replacement.isEmpty || edit.length > 0
        else { return nil }
        let old = source.substring(with: edit)
        guard Self.safeProseEdit(old: old, replacement: replacement),
              edit.length > 0 || Self.isInteriorWordInsertion(source: source, at: edit.location)
              || Self.isInteriorSpaceInsertion(source: source, at: edit.location, replacement: replacement)
        else { return nil }

        guard let editIndex = indexOfEdit(edit) else { return nil }
        let entry = resolvedSection(at: editIndex)
        let node = entry.node
        let localEdit = NSRange(location: edit.location - entry.offset, length: edit.length)
        if Self.paragraph(in: node, overlapping: localEdit) != nil {
            guard Self.admitsParagraphEdit(entry: entry, localEdit: localEdit) else { return nil }
        } else {
            guard Self.isBoundedHeadingEdit(entry: entry, edit: edit, source: source) else { return nil }
        }

        guard firstIndex(overlapping: visible) != nil else { return nil }
        let lower = entry.globalRange.location
        let upper = NSMaxRange(entry.globalRange)
        let delta = (replacement as NSString).length - edit.length
        let newLength = upper - lower + delta
        guard lower <= edit.location, NSMaxRange(edit) <= upper,
              newLength > 0, newLength <= Self.windowLimit,
              lower >= 0, lower + newLength <= source.length + delta
        else { return nil }
        return Window(old: NSRange(location: lower, length: upper - lower),
                      new: NSRange(location: lower, length: newLength),
                      firstSection: editIndex, lastSection: editIndex)
    }

    /// Replace cached trees only after a fresh local parse preserves the
    /// selected root-section shape. On failure the cache is unchanged.
    mutating func replace(_ window: Window, with snapshot: LanguageLayerTreeSnapshot, content: String,
                          delta: Int) throws {
        let (newSourceLength, overflow) = sourceLength.addingReportingOverflow(delta)
        guard window.firstSection >= 0, window.firstSection <= window.lastSection,
              window.lastSection < sections.count,
              !overflow, newSourceLength >= 0,
              window.old.location == window.new.location,
              window.old.location >= 0, window.old.location <= sourceLength,
              window.new.location <= newSourceLength,
              window.old.length > 0, window.new.length > 0,
              window.old.length <= sourceLength - window.old.location,
              window.new.length <= newSourceLength - window.new.location,
              window.new.length == (content as NSString).length,
              delta == window.new.length - window.old.length
        else { throw CacheError.windowMismatch }
        guard let root = snapshot.rootSnapshot.tree.rootNode else { throw CacheError.snapshotUnavailable }
        let expectedCount = window.lastSection - window.firstSection + 1
        guard root.childCount == expectedCount else { throw CacheError.sectionShapeChanged }
        var replacements: [Section] = []
        replacements.reserveCapacity(expectedCount)
        for index in 0 ..< root.childCount {
            guard let node = root.child(at: index) else { throw CacheError.snapshotUnavailable }
            let sectionIndex = window.firstSection + index
            guard let replacementNode = Self.replacementNode(
                node, replacing: sections[sectionIndex].node,
                contentLength: (content as NSString).length, singleEntry: expectedCount == 1
            ) else { throw CacheError.sectionShapeChanged }
            replacements.append(Section(node: replacementNode, snapshot: snapshot, content: content,
                                        offset: window.new.location - shifts.displacement(at: sectionIndex)))
        }
        sections.replaceSubrange(window.firstSection ... window.lastSection, with: replacements)
        shifts.shift(after: window.lastSection, by: delta)
        sourceLength = newSourceLength
    }

    func visibleSections(_ visible: NSRange) -> [Section] {
        guard visible.location != NSNotFound, visible.location >= 0,
              visible.length > 0, visible.location <= sourceLength,
              visible.length <= sourceLength - visible.location
        else { return [] }
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

    /// Resolve the same combined root/injection captures as the full layer,
    /// clipped to the caller's bounded paint authority. No parser or mutable
    /// storage is consulted during this read.
    func tokens(in visible: NSRange) throws -> [Token] {
        guard visible.location != NSNotFound, visible.location >= 0,
              visible.length > 0, visible.length <= Self.windowLimit
        else { return [] }
        var result: [Token] = []
        for section in visibleSections(visible) {
            let clip = NSIntersectionRange(section.globalRange, visible)
            guard clip.length > 0 else { continue }
            let local = NSRange(location: clip.location - section.offset, length: clip.length)
            let captures = try section.snapshot.highlights(
                in: local, provider: section.content.predicateTextProvider
            )
            for capture in captures {
                let shifted = NSRange(location: capture.range.location + section.offset,
                                      length: capture.range.length)
                let bounded = NSIntersectionRange(shifted, clip)
                if bounded.length > 0 {
                    result.append(Token(name: capture.name, range: bounded))
                }
            }
        }
        return result
    }

    func resolvedSection(at index: Int) -> Section {
        var section = sections[index]
        section.offset += shifts.displacement(at: index)
        return section
    }

    /// Split heading hierarchy and paragraphs into disjoint paint/edit entries.
    /// Tree-sitter nests every `##` below a `#`, and a single heading can own
    /// thousands of ordinary paragraphs. Gaps and headings retain the parent
    /// snapshot while paragraphs can be reparsed as bounded local windows.
    private static func partition(_ node: Node, snapshot: LanguageLayerTreeSnapshot,
                                  source: String, into entries: inout [Section]) {
        guard node.nodeType == "section" else {
            entries.append(Section(node: node, snapshot: snapshot, content: source, offset: 0))
            return
        }
        if node.range.length <= windowLimit,
           !(0 ..< node.childCount).contains(where: { node.child(at: $0)?.nodeType == "section" }) {
            entries.append(Section(node: node, snapshot: snapshot, content: source, offset: 0))
            return
        }
        var cursor = node.range.location
        for index in 0 ..< node.childCount {
            guard let child = node.child(at: index),
                  child.nodeType == "section" || child.nodeType == "paragraph"
            else { continue }
            if child.range.location > cursor {
                entries.append(Section(node: node, snapshot: snapshot, content: source, offset: 0,
                                       range: NSRange(location: cursor, length: child.range.location - cursor)))
            }
            if child.nodeType == "section" {
                partition(child, snapshot: snapshot, source: source, into: &entries)
            } else {
                entries.append(Section(node: child, snapshot: snapshot, content: source, offset: 0))
            }
            cursor = NSMaxRange(child.range)
        }
        if cursor < NSMaxRange(node.range) {
            entries.append(Section(node: node, snapshot: snapshot, content: source, offset: 0,
                                   range: NSRange(location: cursor, length: NSMaxRange(node.range) - cursor)))
        }
    }

    private static func paragraph(in node: Node, overlapping edit: NSRange) -> Node? {
        guard !node.hasError else { return nil }
        if node.nodeType == "paragraph" {
            return node
        }
        guard node.nodeType == "section" else { return nil }
        let paragraphs = (0 ..< node.childCount).compactMap { node.child(at: $0) }
            .filter { $0.nodeType == "paragraph" && NSIntersectionRange($0.range, probe(edit)).length > 0 }
        return paragraphs.count == 1 ? paragraphs[0] : nil
    }

    static func admitsParagraphEdit(entry: Section, localEdit: NSRange) -> Bool {
        guard let paragraph = paragraph(in: entry.node, overlapping: localEdit),
              localEdit.location > paragraph.range.location,
              NSMaxRange(localEdit) < NSMaxRange(paragraph.range),
              paragraph.range.length <= windowLimit
        else { return false }
        let paragraphText = (entry.content as NSString).substring(with: paragraph.range)
        let body: String = if paragraphText.hasSuffix("\r\n") {
            // Swift treats CRLF as one Character; drop two UTF-16 units.
            (paragraphText as NSString).substring(to: (paragraphText as NSString).length - 2)
        } else if paragraphText.hasSuffix("\n") {
            String(paragraphText.dropLast())
        } else {
            paragraphText
        }
        return safeProseBody(body)
    }

    private func globalRange(at index: Int) -> NSRange {
        resolvedSection(at: index).globalRange
    }

    func indexOfEdit(_ edit: NSRange) -> Int? {
        firstIndex(overlapping: Self.probe(edit))
    }

    private static func probe(_ range: NSRange) -> NSRange {
        NSRange(location: range.location, length: max(1, range.length))
    }

    func firstIndex(overlapping region: NSRange) -> Int? {
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

extension MarkdownSectionCache {
    // A heading's disjoint cache entry can be reparsed when a plain heading
    // word is split by a newline, or its terminal CRLF is normalized to LF.
    // The bounded entry starts at the heading marker and ends before the next
    // independently cached paragraph/section. Other structural edits retain
    // the full-document fallback because they may change heading hierarchy.
    // swiftlint:disable:next function_body_length
    func selectStructuralHeading(source: NSString, edit: NSRange,
                                 replacement: String, visible: NSRange) -> Window? {
        guard source.length == sourceLength,
              edit.location >= 0, edit.length >= 0,
              edit.location <= source.length,
              edit.length <= source.length - edit.location,
              visible.location != NSNotFound, visible.location >= 0,
              visible.length > 0, visible.location <= source.length,
              visible.length <= source.length - visible.location,
              firstIndex(overlapping: visible) != nil,
              let index = indexOfEdit(edit)
        else { return nil }
        let section = resolvedSection(at: index)
        let oldWindow = section.globalRange
        guard section.node.nodeType == "section",
              oldWindow.length > 0, oldWindow.length <= Self.windowLimit,
              oldWindow.location <= edit.location,
              NSMaxRange(edit) <= NSMaxRange(oldWindow)
        else { return nil }

        let content = source.substring(with: oldWindow) as NSString
        let localEdit = NSRange(location: edit.location - oldWindow.location, length: edit.length)
        let line = content.lineRange(for: NSRange(location: 0, length: 0))
        let lineText = content.substring(with: line)
        let newline = (lineText as NSString).range(of: "\n")
        guard NSMaxRange(localEdit) <= NSMaxRange(line),
              line.length > 3,
              newline.location != NSNotFound
        else { return nil }
        let prefix = (lineText as NSString).substring(to: newline.location)
            .trimmingCharacters(in: .newlines)
        let heading = prefix.drop { $0 == "#" }
        let markerCount = prefix.count - heading.count
        let plain = CharacterSet.alphanumerics.union(.whitespaces)
        guard (1 ... 6).contains(markerCount), heading.first == " "
        else { return nil }

        if replacement == "\n", edit.length == 0 {
            // An interior word split cannot start another Markdown block.
            // Require a blank line after the original heading: otherwise
            // its new second line could combine with a following setext
            // underline outside this cache entry.
            let following = content.substring(from: NSMaxRange(line))
            guard heading.unicodeScalars.allSatisfy(plain.contains),
                  following.hasPrefix("\n") || following.hasPrefix("\r\n"),
                  localEdit.location > markerCount + 1,
                  localEdit.location < (prefix as NSString).length,
                  Self.isInteriorWordInsertion(source: content, at: localEdit.location)
            else { return nil }
        } else if replacement == "\n", edit.length == 2 {
            guard content.substring(with: localEdit) == "\r\n",
                  NSMaxRange(localEdit) == (lineText as NSString).length
            else { return nil }
        } else {
            return nil
        }

        let delta = (replacement as NSString).length - edit.length
        let newLength = oldWindow.length + delta
        guard newLength > 0, newLength <= Self.windowLimit,
              oldWindow.location <= source.length + delta - newLength
        else { return nil }
        return Window(old: oldWindow,
                      new: NSRange(location: oldWindow.location, length: newLength),
                      firstSection: index, lastSection: index)
    }
}

/// Difference index for root-section shifts after bounded edits.
private struct SectionShifts {
    private var tree: [Int]

    init(sectionCount: Int) {
        tree = Array(repeating: 0, count: sectionCount + 1)
    }

    mutating func shift(after index: Int, by delta: Int) {
        var slot = index + 2
        while slot < tree.count {
            tree[slot] += delta
            slot += slot & -slot
        }
    }

    func displacement(at index: Int) -> Int {
        var slot = index + 1
        var result = 0
        while slot > 0 {
            result += tree[slot]
            slot -= slot & -slot
        }
        return result
    }
}

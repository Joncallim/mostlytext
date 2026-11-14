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
    private var sourceLength: Int

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

    // swiftlint:disable cyclomatic_complexity
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
        if let paragraph = Self.paragraph(in: node, overlapping: localEdit) {
            guard localEdit.location > paragraph.range.location,
                  NSMaxRange(localEdit) < NSMaxRange(paragraph.range),
                  paragraph.range.length <= Self.windowLimit
            else { return nil }
            let paragraphText = (entry.content as NSString).substring(with: paragraph.range)
            let body: String
            if paragraphText.hasSuffix("\r\n") {
                body = String(paragraphText.dropLast(2))
            } else if paragraphText.hasSuffix("\n") {
                body = String(paragraphText.dropLast())
            } else {
                body = paragraphText
            }
            guard Self.safeProseBody(body) else { return nil }
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
    // swiftlint:enable cyclomatic_complexity

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
            guard node.nodeType == sections[sectionIndex].node.nodeType else {
                throw CacheError.sectionShapeChanged
            }
            replacements.append(Section(node: node, snapshot: snapshot, content: content,
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

    private func resolvedSection(at index: Int) -> Section {
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

    /// Require both neighboring UTF-16 units to be alphanumeric. This also
    /// refuses surrogate boundaries and word-edge/structural insertions.
    private static func isInteriorWordInsertion(source: NSString, at location: Int) -> Bool {
        guard location > 0, location < source.length else { return false }
        let word = CharacterSet.alphanumerics
        let left = source.substring(with: NSRange(location: location - 1, length: 1))
        let right = source.substring(with: NSRange(location: location, length: 1))
        return left.unicodeScalars.allSatisfy(word.contains)
            && right.unicodeScalars.allSatisfy(word.contains)
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

    private func globalRange(at index: Int) -> NSRange {
        resolvedSection(at: index).globalRange
    }

    private func indexOfEdit(_ edit: NSRange) -> Int? {
        firstIndex(overlapping: Self.probe(edit))
    }

    private static func probe(_ range: NSRange) -> NSRange {
        NSRange(location: range.location, length: max(1, range.length))
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

private extension MarkdownSectionCache {
    static func isInteriorSpaceInsertion(source: NSString, at location: Int, replacement: String) -> Bool {
        guard location > 0, location < source.length,
              !replacement.isEmpty, replacement.unicodeScalars.allSatisfy({ $0 == " " || $0 == "\t" })
        else { return false }
        let word = CharacterSet.alphanumerics
        let left = source.substring(with: NSRange(location: location - 1, length: 1))
        let right = source.substring(with: NSRange(location: location, length: 1))
        return left.unicodeScalars.allSatisfy(word.contains)
            && right.unicodeScalars.allSatisfy({ word.contains($0) || $0 == " " || $0 == "\t" })
    }

    static func safeProseEdit(old: String, replacement: String) -> Bool {
        let word = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        return (old + replacement).unicodeScalars.allSatisfy({ word.contains($0) || $0 == " " || $0 == "\t" })
    }

    /// Links, references, escapes, entities and block syntax can depend on
    /// text outside the local slice. Keep them on the full-parse path.
    static func safeProseBody(_ body: String) -> Bool {
        let word = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        return body.unicodeScalars.allSatisfy({ word.contains($0) || $0 == " " || $0 == "\t"
            || $0 == "*" || $0 == "_" || $0 == "`" })
    }

    static func isBoundedHeadingEdit(entry: Section, edit: NSRange, source: NSString) -> Bool {
        let range = entry.globalRange
        guard entry.node.nodeType == "section", range.length > 0, range.length <= windowLimit,
              range.location <= edit.location, NSMaxRange(edit) <= NSMaxRange(range)
        else { return false }
        let slice = source.substring(with: range)
        guard let lineEnd = slice.firstIndex(of: "\n") else { return false }
        let line = String(slice[..<lineEnd])
        let leadingHashes = line.prefix(while: { $0 == "#" }).count
        guard (1 ... 6).contains(leadingHashes), line.dropFirst(leadingHashes).first == " ",
              slice[lineEnd...].unicodeScalars.allSatisfy({ $0 == "\n" || $0 == "\r" }),
              safeProseBody(String(line.dropFirst(leadingHashes + 1)))
        else { return false }
        let contentStart = range.location + leadingHashes + 1
        let contentEnd = range.location + (line as NSString).length
        return edit.location > contentStart && NSMaxRange(edit) < contentEnd
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

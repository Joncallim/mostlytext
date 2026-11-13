import Foundation
import Neon
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// A conservative Markdown section cache for bounded plain-word edits.
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
        var offset: Int

        var globalRange: NSRange {
            NSRange(location: node.range.location + offset, length: node.range.length)
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
            entries.append(Section(node: node, snapshot: snapshot, content: source, offset: 0))
        }
        sections = entries
        shifts = SectionShifts(sectionCount: entries.count)
        sourceLength = (source as NSString).length
    }

    /// Admit only a replacement wholly inside one bounded plain paragraph.
    /// Keeping section count stable lets later section offsets shift in O(log n).
    func select(source: NSString, edit: NSRange, replacement: String, visible: NSRange) -> Window? {
        let word = CharacterSet.alphanumerics
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
        guard old.unicodeScalars.allSatisfy(word.contains),
              replacement.unicodeScalars.allSatisfy(word.contains)
        else { return nil }

        guard edit.length > 0 || Self.isInteriorWordInsertion(source: source, at: edit.location) else { return nil }

        guard let editIndex = indexOfEdit(edit) else { return nil }
        let entry = resolvedSection(at: editIndex)
        let node = entry.node
        let localEdit = NSRange(location: edit.location - entry.offset, length: edit.length)
        guard node.nodeType == "section", !node.hasError else { return nil }
        let paragraphs = (0 ..< node.childCount).compactMap { node.child(at: $0) }
            .filter { $0.nodeType == "paragraph" && NSIntersectionRange($0.range, Self.probe(localEdit)).length > 0 }
        guard paragraphs.count == 1, let paragraph = paragraphs.first, !paragraph.hasError,
              localEdit.location > paragraph.range.location,
              NSMaxRange(localEdit) < NSMaxRange(paragraph.range),
              paragraph.range.length <= Self.windowLimit
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
              newLength > 0, newLength <= Self.windowLimit,
              lower >= 0, lower + newLength <= source.length + delta
        else { return nil }
        return Window(old: NSRange(location: lower, length: upper - lower),
                      new: NSRange(location: lower, length: newLength),
                      firstSection: first, lastSection: last)
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

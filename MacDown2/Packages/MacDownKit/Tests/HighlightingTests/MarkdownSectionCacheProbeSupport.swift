import AppKit
import Foundation
@testable import Highlighting
import Neon
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

enum SectionProbeLimits {
    static let windowLimit = 65536
}

struct Capture: Equatable, Comparable {
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

@MainActor
final class CapturePublication {
    var tokens: [Token]

    init(_ captures: [Capture]) {
        tokens = captures.map { Token(name: $0.name,
                                      range: NSRange(location: $0.location, length: $0.length)) }
    }

    func replace(with captures: [Capture]) {
        tokens = captures.map { Token(name: $0.name,
                                      range: NSRange(location: $0.location, length: $0.length)) }
    }
}

struct Captures: Equatable {
    let root: [Capture]
    let inline: [Capture]
    let combined: [Capture]

    var isEmpty: Bool {
        root.isEmpty && inline.isEmpty && combined.isEmpty
    }
}

struct Section {
    let node: Node
    let layer: LanguageLayer
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

struct Step {
    let name: String
    let source: String
    let visible: NSRange
    let candidate: Captures
    let windowLength: Int
    let duration: Duration
}

struct EditSpec {
    let name: String
    let needle: String
    let replacement: String
}

@MainActor
struct SectionCache {
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

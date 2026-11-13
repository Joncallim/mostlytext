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

typealias Section = MarkdownSectionCache.Section
typealias Window = MarkdownSectionCache.Window
typealias SectionCache = MarkdownSectionCache

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

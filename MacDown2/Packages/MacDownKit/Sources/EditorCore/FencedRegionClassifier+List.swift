import Foundation

extension FencedRegionClassifier {
    static let maximumListDepth = 32

    struct ListContainer {
        let floor: Int
        let quoteDepth: Int
    }

    struct LineIndent {
        let spaces: Int
        let blank: Bool
        let hasTab: Bool
    }

    struct FenceReplay {
        let text: NSString
        var active: FenceDelimiter?
        var lists: [ListContainer] = []

        mutating func consume(_ line: ScannedLine) -> Bool {
            let indentation = FencedRegionClassifier.indentation(after: line.contentStart, in: text)
            guard prepare(line, indentation: indentation) else { return false }
            if indentation.blank {
                return true
            }
            let context: (start: Int, floor: Int)? = if let opener = active {
                (line.contentStart + opener.listFloor, opener.listFloor)
            } else {
                listContext(for: line, indentation: indentation)
            }
            guard let context else { return false }
            if context.start > line.contentStart + indentation.spaces,
               context.start > MarkdownEditingAssistEngine.lineContentEnd(of: line.contentStart, in: text) {
                return true
            }
            guard let fence = FencedRegionClassifier.fenceDelimiter(
                contentStart: context.start, quoteDepth: line.quoteDepth,
                listFloor: context.floor, in: text
            ), line.caretLimit.map({ $0 >= fence.markerEnd }) ?? true
            else { return true }

            apply(fence)
            return true
        }

        private mutating func prepare(_ line: ScannedLine, indentation: LineIndent) -> Bool {
            if indentation.hasTab, !lists.isEmpty {
                return false
            }
            if let opener = active, opener.quoteDepth > line.quoteDepth {
                active = nil
            }
            while let last = lists.last, last.quoteDepth > line.quoteDepth {
                lists.removeLast()
            }
            if let last = lists.last, line.quoteDepth > last.quoteDepth {
                let physicalIndent = FencedRegionClassifier.indentation(after: line.lineStart, in: text)
                if physicalIndent.spaces >= last.floor {
                    return false
                }
                lists.removeAll()
            }
            if !indentation.blank {
                while let last = lists.last, indentation.spaces < last.floor {
                    lists.removeLast()
                }
            }
            if let opener = active, opener.listFloor > 0,
               !lists.contains(where: { $0.floor == opener.listFloor && $0.quoteDepth == opener.quoteDepth }) {
                active = nil
            }
            return true
        }

        private mutating func apply(_ fence: FenceDelimiter) {
            if let opener = active {
                if fence.canClose, fence.character == opener.character,
                   fence.markerLength >= opener.markerLength,
                   fence.quoteDepth == opener.quoteDepth,
                   fence.listFloor == opener.listFloor {
                    active = nil
                }
            } else {
                active = fence
            }
        }

        private mutating func listContext(
            for line: ScannedLine,
            indentation: LineIndent
        ) -> (start: Int, floor: Int)? {
            let existingFloor = lists.last?.floor ?? 0
            let canStartList = !indentation.hasTab &&
                (lists.isEmpty ? indentation.spaces <= 3 : indentation.spaces <= existingFloor + 3)
            if canStartList,
               FencedRegionClassifier.isListMarkerLead(at: line.contentStart + indentation.spaces, in: text) {
                var markerStart = line.contentStart + indentation.spaces
                var added = false
                let lineEnd = MarkdownEditingAssistEngine.lineContentEnd(of: line.contentStart, in: text)
                while markerStart < lineEnd {
                    if FencedRegionClassifier.tabDelimitedListMarker(
                        at: markerStart, lineEnd: lineEnd, in: text
                    ) {
                        return nil
                    }
                    guard let markerEnd = FencedRegionClassifier.listMarkerContentStart(
                        at: markerStart, lineEnd: lineEnd, in: text
                    ) else { break }
                    guard lists.count < maximumListDepth else { return nil }
                    let floor = markerEnd - line.contentStart
                    lists.append(ListContainer(floor: floor, quoteDepth: line.quoteDepth))
                    markerStart = markerEnd
                    added = true
                }
                if added {
                    // A quote marker after a list marker needs a mixed
                    // container replay. Withhold Markdown assists until that
                    // grammar is available instead of guessing prose.
                    if markerStart < lineEnd, text.character(at: markerStart) == 0x3E {
                        return nil
                    }
                    return (markerStart, markerStart - line.contentStart)
                }
            }
            if !lists.isEmpty, !indentation.blank {
                return (line.contentStart + existingFloor, existingFloor)
            }
            return (line.contentStart, 0)
        }
    }

    static func indentation(
        after contentStart: Int, in text: NSString
    ) -> LineIndent {
        var index = contentStart
        var hasTab = false
        while index < text.length {
            let character = text.character(at: index)
            guard character == 0x20 || character == 0x09 else { break }
            hasTab = hasTab || character == 0x09
            index += 1
        }
        let blank = index == text.length || text.character(at: index) == 0x0A || text.character(at: index) == 0x0D
        return LineIndent(spaces: index - contentStart, blank: blank, hasTab: hasTab)
    }

    /// A local list marker supplies its content indentation. This is a
    /// container prefix only; it never asks the Markdown parser to run on a
    /// keypress. A fifth following space belongs to content indentation.
    static func listMarkerContentStart(at start: Int, lineEnd: Int, in text: NSString) -> Int? {
        guard var end = listMarkerEnd(at: start, lineEnd: lineEnd, in: text) else { return nil }
        if end == lineEnd {
            return end + 1
        }
        if text.character(at: end) == 0x09 {
            return end + 1
        }
        guard text.character(at: end) == 0x20 else { return nil }
        let firstSpace = end
        while end < lineEnd, end - firstSpace < 4, text.character(at: end) == 0x20 {
            end += 1
        }
        return end < lineEnd && text.character(at: end) == 0x20 ? firstSpace + 1 : end
    }

    private static func listMarkerEnd(at start: Int, lineEnd: Int, in text: NSString) -> Int? {
        guard start < lineEnd else { return nil }
        let marker = text.character(at: start)
        if marker == 0x2D || marker == 0x2B || marker == 0x2A { // - + *
            return start + 1
        }
        guard marker >= 0x30, marker <= 0x39 else { return nil }
        var end = start
        var digits = 0
        while end < lineEnd, digits < 9,
              text.character(at: end) >= 0x30, text.character(at: end) <= 0x39 {
            end += 1
            digits += 1
        }
        guard end < lineEnd, text.character(at: end) == 0x2E || text.character(at: end) == 0x29
        else { return nil } // . or )
        return end + 1
    }

    private static func tabDelimitedListMarker(at start: Int, lineEnd: Int, in text: NSString) -> Bool {
        guard let end = listMarkerEnd(at: start, lineEnd: lineEnd, in: text), end < lineEnd else {
            return false
        }
        return text.character(at: end) == 0x09
    }

    private static func isListMarkerLead(at index: Int, in text: NSString) -> Bool {
        guard index < text.length else { return false }
        let character = text.character(at: index)
        return character == 0x2D || character == 0x2B || character == 0x2A ||
            (character >= 0x30 && character <= 0x39)
    }
}

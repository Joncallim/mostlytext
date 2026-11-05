import Foundation

/// Converts numeric Markdown positions using only this input's own scalar boundaries.
/// Foundation positions can retain cached indices from another string; those indices
/// must never be applied to this input through Range(position, in:).
struct PreviewMarkdownSourceMap: Sendable {
    private struct Boundary: Sendable {
        let lowerUTF16: Int
        let upperUTF16: Int
    }

    private let lines: [Range<Int>]
    private let boundaries: [Int: Boundary]
    private let endBoundaries: [Int: Boundary]

    init(_ source: String) {
        var boundaries: [Int: Boundary] = [:]
        var ends: [Int: Boundary] = [:]
        var utf8Offset = 0
        var utf16Offset = 0
        for scalar in source.unicodeScalars {
            let boundary = Boundary(lowerUTF16: utf16Offset, upperUTF16: utf16Offset + scalar.utf16.count)
            boundaries[utf8Offset] = boundary
            // Public positions describe a scalar endpoint. Native parser versions
            // may report the first or inclusive final UTF-8 byte for the end column.
            ends[utf8Offset] = boundary
            ends[utf8Offset + scalar.utf8.count - 1] = boundary
            utf8Offset += scalar.utf8.count
            utf16Offset += scalar.utf16.count
        }
        self.boundaries = boundaries
        endBoundaries = ends
        let bytes = Array(source.utf8)
        var lines: [Range<Int>] = []
        var start = 0
        var cursor = 0
        while cursor < bytes.count {
            if bytes[cursor] == 13 || bytes[cursor] == 10 {
                lines.append(start ..< cursor)
                if bytes[cursor] == 13, cursor + 1 < bytes.count, bytes[cursor + 1] == 10 {
                    cursor += 1
                }
                start = cursor + 1
            }
            cursor += 1
        }
        lines.append(start ..< bytes.count)
        self.lines = lines
    }

    func range(for position: AttributedString.MarkdownSourcePosition) -> NSRange? {
        guard let start = byteOffset(line: position.startLine, column: position.startColumn),
              let end = byteOffset(line: position.endLine, column: position.endColumn),
              start <= end, let lower = boundaries[start], let upper = endBoundaries[end]
        else { return nil }
        return NSRange(location: lower.lowerUTF16, length: upper.upperUTF16 - lower.lowerUTF16)
    }

    private func byteOffset(line: Int, column: Int) -> Int? {
        guard line > 0, line <= lines.count, column > 0 else { return nil }
        let range = lines[line - 1]
        guard column <= range.count else { return nil }
        return range.lowerBound + column - 1
    }
}

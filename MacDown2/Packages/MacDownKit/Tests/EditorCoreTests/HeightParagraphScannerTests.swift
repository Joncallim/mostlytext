@testable import EditorCore
import Foundation
import Testing

struct HeightParagraphScannerTests {
    @Test func mixedSeparatorsKeepCRLFAndTheFinalEmptyParagraph() {
        #expect(ranges("one\r\ntwo\rlast\u{2029}" as NSString) == [
            NSRange(location: 0, length: 3), NSRange(location: 5, length: 3),
            NSRange(location: 9, length: 4), NSRange(location: 14, length: 0),
        ])
    }

    @Test func emptyTextAndNonParagraphBreaksKeepTheirOriginalCoordinates() {
        #expect(ranges("" as NSString) == [NSRange(location: 0, length: 0)])
        let text = "a\u{2028}b\u{0085}c\u{000B}d\u{000C}e" as NSString
        #expect(ranges(text) == [NSRange(location: 0, length: text.length)])
    }

    @Test func generatedUnicodeAndMalformedUTF16MatchTheOriginalLoop() {
        let tokens: [[unichar]] = [
            [], [0x61], [0x0A], [0x0D], [0x2029],
            [0xD800], [0xDC00], [0xD83D, 0xDE42], [0x2028], [0x85],
        ]
        for seed in 0 ..< 10000 {
            var code = seed
            var units: [unichar] = []
            for _ in 0 ..< 4 {
                units += tokens[code % tokens.count]
                code /= tokens.count
            }
            let text = units.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return NSString(string: "") }
                return NSString(characters: base, length: buffer.count)
            }
            #expect(ranges(text) == legacyRanges(text), "UTF-16 sequence \(units)")
        }
    }

    @Test func chunkEdgesPreserveCRLFAndSurrogateCoordinates() {
        let prefix = String(repeating: "a", count: HeightParagraphScanner.chunkCapacity - 1)
        let text = (prefix + "\r\nb\u{2029}") as NSString
        #expect(ranges(text) == legacyRanges(text))
        let units = Array(prefix.utf16) + [0xD800, 0xDC00, 0x0A, 0x0D, 0x0A]
        let raw = units.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return NSString(string: "") }
            return NSString(characters: base, length: buffer.count)
        }
        #expect(ranges(raw) == legacyRanges(raw))
    }

    private func ranges(_ text: NSString) -> [NSRange] {
        var result: [NSRange] = []
        HeightParagraphScanner.forEach(in: text) { result.append($0) }
        return result
    }

    /// Exact pre-change boundary loop retained as a comparison oracle.
    private func legacyRanges(_ string: NSString) -> [NSRange] {
        let length = string.length
        var ranges: [NSRange] = []
        var start = 0
        var index = 0
        while index < length {
            let unit = string.character(at: index)
            if unit == 0x0A || unit == 0x0D || unit == 0x2029 {
                ranges.append(NSRange(location: start, length: index - start))
                if unit == 0x0D, index + 1 < length, string.character(at: index + 1) == 0x0A {
                    index += 1
                }
                index += 1
                start = index
            } else {
                index += 1
            }
        }
        ranges.append(NSRange(location: start, length: length - start))
        return ranges
    }
}

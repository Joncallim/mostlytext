import Foundation

/// A parsed YAML value. Our own tree — Yams never leaks (D3).
public enum FrontMatterValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case number(Double)
    case bool(Bool)
    case array([FrontMatterValue])
    case dictionary([String: FrontMatterValue])
    case null
}

/// A leading `--- … ---` block. Present iff the delimiters were found (D3).
public struct FrontMatter: Sendable, Equatable {
    /// YAML text between the delimiter lines, with line endings normalized to LF
    /// for parsing. This derived value never replaces the authored source text.
    public let raw: String

    /// 1-based lines of the ORIGINAL source, INCLUDING both delimiter lines.
    public let lineRange: ClosedRange<Int>

    /// Parsed mapping, or nil when the YAML is malformed or not a mapping.
    public let values: [String: FrontMatterValue]?

    public init(raw: String, lineRange: ClosedRange<Int>, values: [String: FrontMatterValue]?) {
        self.raw = raw
        self.lineRange = lineRange
        self.values = values
    }
}

/// Delimiter-defined front-matter extraction (D3).
///
/// Front matter exists iff line 1 is `---` (with optional trailing whitespace)
/// and a later line is `---` or `...` (with optional trailing whitespace), and
/// line 2 is not blank.
/// This type does not import Yams; YAML parsing happens in `ParseEngine.swift`.
enum FrontMatterExtractor {
    struct Extraction {
        let raw: String
        let closingLineNumber: Int
        let body: String
    }

    static func extract(from text: String) -> Extraction? {
        let lines = text.lines()

        guard !lines.isEmpty else {
            return nil
        }

        let opener = lines[0]
        // §4.4 rule 1: strip a single leading U+FEFF for detection only.
        // SourceMap offsets continue to count the BOM as part of the content.
        let openerText = opener.text.hasPrefix("\u{FEFF}")
            ? String(opener.text.dropFirst())
            : opener.text
        guard isDelimiter(openerText, allowed: ["---"]) else {
            return nil
        }

        // A blank line right after the opener means it is a thematic break, not a
        // metadata block (Pandoc's rule): otherwise a horizontal rule at the top of a
        // document swallowed everything up to the next `---` into hidden "front matter".
        if lines.count > 1, lines[1].text.trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }

        for index in 1 ..< lines.count {
            let line = lines[index]
            if isDelimiter(line.text, allowed: ["---", "..."]) {
                let raw = lines[1 ..< index].map(\.text).joined(separator: "\n")
                let closingLineNumber = line.lineNumber
                let body = String(text.suffix(from: line.endOffset))

                return Extraction(raw: raw, closingLineNumber: closingLineNumber, body: body)
            }
        }

        // No closer: the lone opener is a CommonMark thematic break.
        return nil
    }

    private static func isDelimiter(_ line: String, allowed: [String]) -> Bool {
        // YAML front-matter delimiters must begin at column 1; only trailing
        // whitespace is permitted.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard allowed.contains(trimmed) else { return false }
        return line.hasPrefix(trimmed)
    }
}

struct LineInfo {
    let text: String
    let lineNumber: Int
    let startOffset: Int
    let endOffset: Int
}

extension String {
    /// Splits the string into 1-based line records. A trailing newline produces
    /// a final empty line, matching how editors and `SourceMap` count lines.
    func lines() -> [LineInfo] {
        var result: [LineInfo] = []
        var lineNumber = 1
        var lineStartOffset = 0

        let utf16 = utf16
        var currentLineStart = utf16.startIndex

        while true {
            var lineEnd = currentLineStart
            while lineEnd < utf16.endIndex {
                if utf16[lineEnd] == 0x000A || utf16[lineEnd] == 0x000D {
                    break
                }
                lineEnd = utf16.index(after: lineEnd)
            }

            let lineText = String(decoding: utf16[currentLineStart ..< lineEnd], as: UTF16.self)
            var resume = lineEnd
            if resume < utf16.endIndex {
                let wasCarriageReturn = utf16[resume] == 0x000D
                resume = utf16.index(after: resume)
                if wasCarriageReturn, resume < utf16.endIndex, utf16[resume] == 0x000A {
                    resume = utf16.index(after: resume)
                }
            }
            let endOffset = lineStartOffset + utf16.distance(from: currentLineStart, to: resume)

            result.append(LineInfo(
                text: lineText,
                lineNumber: lineNumber,
                startOffset: lineStartOffset,
                endOffset: endOffset
            ))

            if lineEnd == utf16.endIndex {
                break
            }
            currentLineStart = resume
            lineStartOffset = endOffset
            lineNumber += 1
        }

        return result
    }

    func suffix(from offset: Int) -> String {
        guard offset > 0 else {
            return self
        }
        guard offset < utf16.count else {
            return ""
        }
        let start = String.Index(utf16Offset: offset, in: self)
        return String(self[start...])
    }
}

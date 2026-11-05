import Foundation

extension DerivedContentComposer {
    /// Immutable inputs shared by every contribution validation in one compose
    /// pass. Grouped so the per-contribution validator does not re-carry four
    /// fixed parameters, and so the O(n) UTF-16 length is measured once rather
    /// than once per contribution.
    struct ValidationContext {
        let bodyUTF16Length: Int
        let bodyStartOffset: Int
        let sourceUTF16Length: Int
        let sourceGeneration: UInt
        let sentinelSuffix: String
        let budget: ExportResourceBudget
        /// Source-coordinate UTF-16 ranges of every block quote and list item.
        let containerRanges: [Range<Int>]
        let bodyText: NSString
        let namespaceSVGIDs: Bool

        /// Whether the contributed range opens with a code-fence line (after any quote/list/indent prefix).
        func startsFence(_ bodyRange: Range<Int>) -> Bool {
            guard bodyRange.lowerBound < bodyText.length else { return false }
            let line = bodyText.lineRange(for: NSRange(location: bodyRange.lowerBound, length: 0))
            let first = Self.strippingContainerPrefix(bodyText.substring(with: line)[...])
            return first.hasPrefix("```") || first.hasPrefix("~~~")
        }

        /// Whether the range is the whole logical line: only whitespace and quote/list markers before it,
        /// only whitespace after it. A block placement is only faithful then; mid-line (a table cell, a
        /// heading, emphasis, a link, a paragraph) a blank-line-delimited sentinel would split the construct.
        func occupiesWholeLines(_ bodyRange: Range<Int>) -> Bool {
            guard bodyRange.lowerBound <= bodyText.length, bodyRange.upperBound <= bodyText.length else { return false }
            let startLine = bodyText.lineRange(for: NSRange(location: bodyRange.lowerBound, length: 0))
            let before = bodyText.substring(
                with: NSRange(location: startLine.location, length: bodyRange.lowerBound - startLine.location)
            )
            guard Self.strippingContainerPrefix(before[...]).allSatisfy(\.isWhitespace) else { return false }
            let endLine = bodyText.lineRange(for: NSRange(location: bodyRange.upperBound, length: 0))
            let afterLength = max(0, NSMaxRange(endLine) - bodyRange.upperBound)
            let after = bodyText.substring(with: NSRange(location: bodyRange.upperBound, length: afterLength))
            guard after.allSatisfy(\.isWhitespace) else { return false }
            // A contribution that is the whole content line of a setext heading must stay inline:
            // a blank-line-delimited block would turn the heading into a paragraph plus a rule.
            // A closed fence can never be setext content, so a `---` after it is just a thematic break.
            guard !startsFence(bodyRange) else { return true }
            let nextStart = NSMaxRange(endLine)
            guard nextStart < bodyText.length else { return true }
            let nextLine = bodyText.lineRange(for: NSRange(location: nextStart, length: 0))
            let next = Self.strippingContainerPrefix(bodyText.substring(with: nextLine)[...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isUnderline = !next.isEmpty && (next.allSatisfy { $0 == "=" } || next.allSatisfy { $0 == "-" })
            return !isUnderline
        }

        /// Drops any leading run of indentation, `>` quote markers and list markers (`-`, `+`, `*`, `1.`, `1)`).
        static func strippingContainerPrefix(_ line: Substring) -> Substring {
            var rest = line
            while true {
                let trimmed = rest.drop { $0 == " " || $0 == "\t" || $0 == ">" }
                var next = trimmed
                if let marker = trimmed.first, "-+*".contains(marker), trimmed.dropFirst().first?.isWhitespace == true {
                    next = trimmed.dropFirst()
                } else {
                    let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
                    let afterDigits = trimmed.dropFirst(digits.count)
                    if !digits.isEmpty, let punctuation = afterDigits.first, punctuation == "." || punctuation == ")",
                       afterDigits.dropFirst().first?.isWhitespace == true {
                        next = afterDigits.dropFirst()
                    }
                }
                if next.startIndex == rest.startIndex {
                    return trimmed
                }
                rest = next
            }
        }
    }
}

import Foundation

/// Turns renderer-neutral derived-content contributions into the two things the
/// cmark bridge needs: a body text whose contributed ranges are replaced by
/// deterministic sentinels, and the custom-node specs that turn those sentinels
/// back into derived HTML.
///
/// Failure semantics (issue #49): a failed, stale, out-of-bounds, empty, or
/// overlapping contribution is *not* spliced — its authored Markdown remains in
/// the body and is parsed normally — and an error diagnostic records the reason.
/// Diagnostics a contribution carries are always forwarded, whether or not it is
/// placed, so nothing a renderer reported is silently dropped. There is exactly
/// one pass and no re-parse, so the fallback is bounded by construction.
enum DerivedContentComposer {
    struct Result {
        let splicedBody: String
        /// Requested only by generated-heading analysis. Ordinary export
        /// does not allocate a map or hash the body a second time.
        let coordinates: SplicedBodySourceMap?
        let customNodes: [CMarkGFM.CustomNodeSpec]
        let diagnostics: [ExportDiagnostic]
        let sentinelSuffix: String
        let markedRoots: [SVGIDNamespace.MarkedRoot]
        let markedSourceRanges: [Range<Int>]
    }

    /// One accepted replacement: a body-relative UTF-16 range and the sentinel
    /// that stands in for it until the cmark tree walk substitutes it back.
    struct Splice {
        let range: Range<Int>
        let sentinel: String
        let isBlock: Bool

        var renderedText: String {
            isBlock ? "\n\n\(sentinel)\n\n" : sentinel
        }
    }

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

    static func compose(
        bodyText: String,
        bodyStartOffset: Int,
        sourceUTF16Length: Int,
        contributions: [ExportDerivedContribution],
        sourceGeneration: UInt,
        budget: ExportResourceBudget = .standard,
        containerRanges: [Range<Int>] = [],
        recordCoordinates: Bool = false,
        namespaceSVGIDs: Bool = false
    ) -> Result {
        guard !contributions.isEmpty else {
            return Result(
                splicedBody: bodyText,
                coordinates: recordCoordinates
                    ? SplicedBodySourceMap(sourceText: bodyText, renderedText: bodyText, splices: []) : nil,
                customNodes: [], diagnostics: [], sentinelSuffix: "",
                markedRoots: [], markedSourceRanges: []
            )
        }

        let context = ValidationContext(
            bodyUTF16Length: bodyText.utf16.count,
            bodyStartOffset: bodyStartOffset,
            sourceUTF16Length: sourceUTF16Length,
            sourceGeneration: sourceGeneration,
            // One scan of the body picks a sentinel family that cannot collide
            // with authored text, rather than re-scanning per contribution.
            sentinelSuffix: sentinelSuffix(notCollidingWith: bodyText),
            budget: budget,
            containerRanges: containerRanges,
            bodyText: bodyText as NSString,
            namespaceSVGIDs: namespaceSVGIDs
        )

        let sorted = contributions.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
        var plan = DerivedContentPlan()
        for (index, contribution) in sorted.enumerated() {
            plan.consider(contribution, index: index, context: context)
        }

        let splicedBody = splice(plan.splices, into: bodyText)
        return Result(
            splicedBody: splicedBody,
            coordinates: recordCoordinates
                ? SplicedBodySourceMap(sourceText: bodyText, renderedText: splicedBody, splices: plan.splices) : nil,
            customNodes: plan.customNodes,
            diagnostics: plan.diagnostics,
            sentinelSuffix: context.sentinelSuffix,
            markedRoots: plan.markedRoots,
            markedSourceRanges: plan.markedSourceRanges
        )
    }

    /// The sorted-contribution indices whose sentinel text is still in the RENDERED HTML. A sentinel is replaced
    /// only where cmark parses it as ordinary text; inside a link destination or title, a reference definition,
    /// an HTML attribute or similar it stays as the sentinel string, which must never reach an export.
    static func leakedSentinelIndices(in html: String, suffix: String) -> Set<Int> {
        guard html.range(of: "E12", options: .literal) != nil else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: suffix)
        guard let expression = try? NSRegularExpression(
            pattern: "E12(?:BLOCK|INLINE)" + escaped + "(\\d+)Z"
        ) else { return [] }
        let nsHTML = html as NSString
        var indices: Set<Int> = []
        for match in expression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            if let index = Int(nsHTML.substring(with: match.range(at: 1))) {
                indices.insert(index)
            }
        }
        return indices
    }

    private static let blockSentinelBase = "E12BLOCK"
    private static let inlineSentinelBase = "E12INLINE"

    /// The shortest suffix that makes *both* sentinel families absent from the
    /// authored body. Because `E12BLOCK` is a prefix of every block sentinel,
    /// one containment check per family clears every sentinel that follows.
    private static func sentinelSuffix(notCollidingWith bodyText: String) -> String {
        // One literal scan per family, remembering the longest run of `_` that follows an occurrence: the shortest
        // colliding-free suffix is one underscore longer than that run (or empty when there is no occurrence). Adding
        // an underscore per pass and rescanning the whole body was quadratic in a hostile `E12BLOCK____…` run.
        var longestRun = -1
        for base in [blockSentinelBase, inlineSentinelBase] {
            var searchStart = bodyText.startIndex
            while searchStart < bodyText.endIndex,
                  let hit = bodyText.range(of: base, options: .literal, range: searchStart ..< bodyText.endIndex) {
                var run = 0
                var cursor = hit.upperBound
                while cursor < bodyText.endIndex, bodyText.unicodeScalars[cursor] == "_" {
                    run += 1
                    cursor = bodyText.unicodeScalars.index(after: cursor)
                }
                longestRun = max(longestRun, run)
                searchStart = cursor
            }
        }
        return longestRun < 0 ? "" : String(repeating: "_", count: longestRun + 1)
    }

    /// `<family><suffix><index>Z`. The trailing `Z` terminates the digit run so
    /// no sentinel is ever a prefix — or a substring — of another (`…1Z` cannot
    /// be found inside `…10Z`).
    static func makeSentinel(isBlock: Bool, index: Int, suffix: String) -> String {
        let base = isBlock ? blockSentinelBase : inlineSentinelBase
        return "\(base)\(suffix)\(index)Z"
    }

    /// Builds the body with each valid range replaced by its sentinel. Block
    /// sentinels are surrounded by blank lines so they form a standalone
    /// paragraph; inline sentinels replace the range in place.
    ///
    /// The body is materialised as UTF-16 code units once. Converting each
    /// offset with `String.Index(utf16Offset:in:)` instead would walk the string
    /// from the start for every boundary, which is quadratic in the number of
    /// contributions.
    private static func splice(_ splices: [Splice], into bodyText: String) -> String {
        guard !splices.isEmpty else { return bodyText }

        let units = Array(bodyText.utf16)
        var result = ""
        result.reserveCapacity(bodyText.utf8.count + splices.count * 24)
        var cursor = 0

        func appendUnits(upTo end: Int) {
            let clampedEnd = min(max(end, cursor), units.count)
            guard cursor < clampedEnd else { return }
            result += String(decoding: units[cursor ..< clampedEnd], as: UTF16.self)
            cursor = clampedEnd
        }

        for entry in splices {
            appendUnits(upTo: entry.range.lowerBound)
            result += entry.renderedText
            // Jump past the replaced range; its characters are not emitted.
            cursor = min(max(entry.range.upperBound, cursor), units.count)
        }
        appendUnits(upTo: units.count)

        return result
    }
}

/// The running decision state of one compose pass: what has been accepted so
/// far, and what has been reported.
private struct DerivedContentPlan {
    var diagnostics: [ExportDiagnostic] = []
    var customNodes: [CMarkGFM.CustomNodeSpec] = []
    var splices: [DerivedContentComposer.Splice] = []
    var markedRoots: [SVGIDNamespace.MarkedRoot] = []
    var markedSourceRanges: [Range<Int>] = []

    private var previousBodyUpperBound = 0
    private var placedCount = 0
    private var aggregateDerivedBytes = 0

    mutating func consider(
        _ contribution: ExportDerivedContribution,
        index: Int,
        context: DerivedContentComposer.ValidationContext
    ) {
        // The renderer's own observations are forwarded either way; only an
        // error-level one blocks placement.
        diagnostics.append(contentsOf: contribution.diagnostics)

        let range = contribution.sourceRange
        let bodyRange = (range.lowerBound - context.bodyStartOffset) ..< (range.upperBound - context.bodyStartOffset)

        if let failure = rejection(for: contribution, bodyRange: bodyRange, context: context) {
            diagnostics.append(ExportDiagnostic(severity: .error, message: failure))
            return
        }

        var isBlock = contribution.placement == .block
        if isBlock {
            // A blank-line-delimited sentinel ends whatever construct it sits in. Mid-line (table cell, heading,
            // emphasis, link, paragraph text) the contribution stays an inline fragment. On its own lines inside a
            // list item or block quote it also stays inline (display math) — except a diagram fence, whose lines
            // carry the container's own prefixes and cannot be lifted out cleanly: it stays as authored source.
            if !context.occupiesWholeLines(bodyRange) {
                isBlock = false
            } else if context.containerRanges.contains(where: { $0.contains(range.lowerBound) }) {
                guard !context.startsFence(bodyRange) else {
                    diagnostics.append(ExportDiagnostic(
                        severity: .warning,
                        message: ExportDerivedDiagnosticText.nestedDiagram
                    ))
                    return
                }
                isBlock = false
            }
        }
        let sentinel = DerivedContentComposer.makeSentinel(
            isBlock: isBlock,
            index: index,
            suffix: context.sentinelSuffix
        )
        let sanitized = DerivedHTMLSanitizer.sanitized(contribution.html)
        var preparedHTML = sanitized
        if context.namespaceSVGIDs, sanitized.lowercased().contains("<svg") {
            guard let namespaced = SVGIDNamespace.rewriteMarked(sanitized, occurrence: index) else {
                diagnostics.append(ExportDiagnostic(
                    severity: .error,
                    message: ExportDerivedDiagnosticText.unsafeSVG
                ))
                return
            }
            preparedHTML = namespaced.html
            markedRoots.append(contentsOf: namespaced.roots)
            markedSourceRanges.append(contribution.sourceRange)
        }
        customNodes.append(CMarkGFM.CustomNodeSpec(sentinel: sentinel,
                                                   isBlock: isBlock,
                                                   html: preparedHTML))
        splices.append(DerivedContentComposer.Splice(range: bodyRange, sentinel: sentinel, isBlock: isBlock))
        previousBodyUpperBound = bodyRange.upperBound
        placedCount += 1
        aggregateDerivedBytes += contribution.html.utf8.count
    }

    /// Why this contribution cannot be placed, or `nil` when it can be.
    private func rejection(
        for contribution: ExportDerivedContribution,
        bodyRange: Range<Int>,
        context: DerivedContentComposer.ValidationContext
    ) -> String? {
        if contribution.diagnostics.contains(where: { $0.severity == .error }) {
            return ExportDerivedDiagnosticText.rendererFailure
        }
        if contribution.sourceGeneration != context.sourceGeneration {
            return ExportDerivedDiagnosticText.stale(contribution.sourceGeneration, expected: context.sourceGeneration)
        }
        if contribution.sourceRange.lowerBound < context.bodyStartOffset
            || contribution.sourceRange.upperBound > context.sourceUTF16Length {
            return ExportDerivedDiagnosticText.outsideDocument(contribution.sourceRange)
        }
        if contribution.sourceRange.lowerBound >= contribution.sourceRange.upperBound {
            return ExportDerivedDiagnosticText.emptyRange
        }
        if bodyRange.upperBound > context.bodyUTF16Length {
            return ExportDerivedDiagnosticText.beyondBody
        }
        if bodyRange.lowerBound < previousBodyUpperBound {
            return ExportDerivedDiagnosticText.overlappingRange
        }
        if contribution.html.isEmpty {
            return ExportDerivedDiagnosticText.emptyHTML
        }
        return budgetRejection(for: contribution, budget: context.budget)
    }

    /// A budget violation rejects that one contribution and preserves its
    /// authored source; it never fails the export.
    private func budgetRejection(
        for contribution: ExportDerivedContribution,
        budget: ExportResourceBudget
    ) -> String? {
        guard placedCount < budget.maxDerivedFragmentCount else {
            return ExportDerivedDiagnosticText.fragmentLimit(budget.maxDerivedFragmentCount)
        }
        let (total, overflowed) = aggregateDerivedBytes.addingReportingOverflow(contribution.html.utf8.count)
        guard !overflowed, total <= budget.maxAggregateDerivedHTMLBytes else {
            let limit = ExportResourceBudget.describe(bytes: budget.maxAggregateDerivedHTMLBytes)
            return ExportDerivedDiagnosticText.totalLimit(limit)
        }
        return nil
    }
}

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
        var acceptedHeadingTOCRanges: Set<Range<Int>> = []
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

    static func compose(
        bodyText: String,
        bodyStartOffset: Int,
        sourceUTF16Length: Int,
        contributions: [ExportDerivedContribution],
        sourceGeneration: UInt,
        budget: ExportResourceBudget = .standard,
        containerRanges: [Range<Int>] = [],
        recordCoordinates: Bool = false,
        namespaceSVGIDs: Bool = false,
        svgNamespaceFamily: String? = nil,
        referenceContext: ReferenceContext? = nil
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
            namespaceSVGIDs: namespaceSVGIDs,
            svgNamespaceFamily: svgNamespaceFamily
        )

        let sorted = contributions.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
        var plan = DerivedContentPlan()
        for (index, contribution) in sorted.enumerated() {
            plan.consider(contribution, index: index, context: context)
        }

        return finalize(plan, bodyText: bodyText, context: context,
                        referenceContext: referenceContext, recordCoordinates: recordCoordinates)
    }

    private static func finalize(
        _ plan: DerivedContentPlan, bodyText: String, context: ValidationContext,
        referenceContext: ReferenceContext?, recordCoordinates: Bool
    ) -> Result {
        let splices: [Splice]
        do {
            splices = try preservingReferences(
                plan.splices, bodyText: bodyText, context: context,
                referenceContext: referenceContext
            )
        } catch {
            return Result(
                splicedBody: bodyText,
                coordinates: recordCoordinates
                    ? SplicedBodySourceMap(sourceText: bodyText, renderedText: bodyText, splices: []) : nil,
                customNodes: [],
                diagnostics: plan.diagnostics + [ExportDiagnostic(severity: .error, message: referenceRepairFailure)],
                sentinelSuffix: context.sentinelSuffix, markedRoots: [], markedSourceRanges: []
            )
        }
        let splicedBody = splice(splices, into: bodyText)
        return Result(
            splicedBody: splicedBody,
            coordinates: recordCoordinates
                ? SplicedBodySourceMap(sourceText: bodyText, renderedText: splicedBody, splices: splices) : nil,
            customNodes: plan.customNodes,
            diagnostics: plan.diagnostics,
            sentinelSuffix: context.sentinelSuffix,
            markedRoots: plan.markedRoots,
            markedSourceRanges: plan.markedSourceRanges,
            acceptedHeadingTOCRanges: plan.acceptedHeadingTOCRanges
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
    var acceptedHeadingTOCRanges: Set<Range<Int>> = []

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
        guard let preparedHTML = prepareHTML(contribution, index: index, context: context) else {
            diagnostics.append(ExportDiagnostic(severity: .error, message: ExportDerivedDiagnosticText.unsafeSVG))
            return
        }
        customNodes.append(CMarkGFM.CustomNodeSpec(sentinel: sentinel,
                                                   isBlock: isBlock,
                                                   html: preparedHTML))
        splices.append(DerivedContentComposer.Splice(range: bodyRange, sentinel: sentinel, isBlock: isBlock))
        if contribution.requiresHeadingNavigation {
            acceptedHeadingTOCRanges.insert(contribution.sourceRange)
        }
        previousBodyUpperBound = bodyRange.upperBound
        placedCount += 1
        aggregateDerivedBytes += contribution.html.utf8.count
    }

    private mutating func prepareHTML(
        _ contribution: ExportDerivedContribution, index: Int, context: DerivedContentComposer.ValidationContext
    ) -> String? {
        let sanitized = DerivedHTMLSanitizer.sanitized(contribution.html)
        guard context.namespaceSVGIDs || context.svgNamespaceFamily != nil else { return sanitized }
        guard sanitized.range(of: "<svg", options: .caseInsensitive) != nil else { return sanitized }
        if context.namespaceSVGIDs {
            guard let namespaced = SVGIDNamespace.rewriteMarked(sanitized, occurrence: index) else { return nil }
            markedRoots.append(contentsOf: namespaced.roots)
            markedSourceRanges.append(contribution.sourceRange)
            return namespaced.html
        }
        if let family = context.svgNamespaceFamily {
            return SVGIDNamespace.rewrite(sanitized, occurrence: index, family: family)
        }
        return sanitized
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

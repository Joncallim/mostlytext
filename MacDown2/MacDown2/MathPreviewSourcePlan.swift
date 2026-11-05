import Foundation
import MarkdownEngine
import Math
import MathRendering
import Preview

struct MathPreviewNotice: Sendable, Identifiable {
    let id: UUID
    let message: String
    let kind: MathEquationDiagnostic.Kind
    let sourceID: UUID?
}

struct MathPreviewSourceRequest: Sendable {
    let source: String
    let document: MarkdownDocument
    let blocks: [PreviewBlock]
    let evaluation: MathEvaluation
    let presentation: MathPresentationPlan
}

/// Source planning stays separate from native geometry and attachment creation.
/// Every parsed block is derived from its own original, bounded source interval.
struct MathPreviewSourcePlan: Sendable {
    enum Block: Sendable { case parsed(PreviewMathInput), literal }
    var blocks: [UUID: Block] = [:]
    var drawableEntries: [MathEvaluation.Entry] = []
    var notices: [MathPreviewNotice] = []
    var locations: [UUID: MathPreviewSourceLocation] = [:]
}

enum MathPreviewSourcePlanner {
    private struct Context {
        let original: NSString
        let edits: [MarkdownReferenceRepair.Edit]
        let references: MarkdownReferenceReplayIndex
    }

    static func prepare(_ request: MathPreviewSourceRequest) async throws -> MathPreviewSourcePlan {
        try Task.checkCancellation()
        guard request.document.isBound(to: request.source), let facts = request.document.sourceFacts,
              facts.sourceSHA256 == request.evaluation.analysis.sourceSHA256,
              request.document.revision == request.evaluation.analysis.revision
        else { throw MathAnalysisError.sourceMismatch }
        let references = try MarkdownReferenceReplayIndex(facts: facts)
        let entries = request.presentation.entries
        let edits = try MarkdownReferenceRepair.edits(source: request.source, facts: facts,
                                                      replacing: entries.map(\.equation.syntax.fullRange))
        let context = Context(original: request.source as NSString, edits: edits, references: references)
        var result = initial(request)
        for block in request.blocks {
            try Task.checkCancellation()
            await Task.yield()
            guard let anchor = block.sourceAnchor else { continue }
            var own: [MathEvaluation.Entry] = []
            do {
                own = try select(entries, range: anchor.range, originalRange: \.equation.syntax.fullRange)
                if block.isOversize || request.presentation.literalRemainderRange?.overlaps(anchor.range) == true {
                    result.blocks[block.id] = .literal
                    continue
                }
                let input = try input(block: block, context: context, entries: own)
                result.blocks[block.id] = .parsed(input)
                result.drawableEntries.append(contentsOf: own)
            } catch {
                result.blocks[block.id] = .literal
                if let equation = own.first?.equation {
                    let kind: MathEquationDiagnostic.Kind = (error as? PreviewMathInput.Failure) == .oversizedInput
                        ? .resourceLimit : .internalFailure
                    if !result.notices.contains(where: { $0.id == equation.id }) {
                        result.notices.append(notice(.init(equationID: equation.id, kind: kind,
                                                           sourceOffset: equation.syntax.bodyRange.lowerBound),
                                                     document: request.document))
                    }
                }
            }
        }
        try Task.checkCancellation()
        return result
    }

    private static func initial(_ request: MathPreviewSourceRequest) -> MathPreviewSourcePlan {
        var result = MathPreviewSourcePlan()
        for entry in request.evaluation.entries {
            let offset: Int
            if case let .rejected(problem) = entry.outcome {
                result.notices.append(notice(problem, document: request.document))
                offset = problem.sourceOffset
            } else {
                offset = entry.equation.syntax.bodyRange.lowerBound
            }
            result.locations[entry.id] = .init(range: entry.equation.syntax.fullRange, diagnosticOffset: offset)
        }
        if let range = request.presentation.literalRemainderRange, let id = request.presentation.literalRemainderID {
            result.locations[id] = .init(range: range, diagnosticOffset: range.lowerBound)
            result.notices.append(.init(
                id: id,
                message: MathDiagnosticText.remainder,
                kind: .resourceLimit,
                sourceID: id
            ))
        }
        return result
    }

    static func notice(_ problem: MathEquationDiagnostic, document: MarkdownDocument) -> MathPreviewNotice {
        let line = document.sourceMap.line(atUTF16Offset: problem.sourceOffset)
        let column = problem.sourceOffset - document.sourceMap.lineStartOffsets[line - 1] + 1
        return .init(id: problem.equationID,
                     message: MathDiagnosticText.located(problem.kind, line: line, column: column),
                     kind: problem.kind, sourceID: problem.equationID)
    }

    private static func input(
        block: PreviewBlock, context: Context, entries: [MathEvaluation.Entry]
    ) throws -> PreviewMathInput {
        let original = context.original
        let references = context.references
        guard let anchor = block.sourceAnchor, anchor.sourceSHA256 == references.sourceSHA256,
              !anchor.range.isEmpty, anchor.range.lowerBound >= 0, anchor.range.upperBound <= original.length,
              boundary(anchor.range.lowerBound, in: original), boundary(anchor.range.upperBound, in: original),
              original.substring(with: .init(location: anchor.range.lowerBound, length: anchor.range.count))
              .utf8.elementsEqual(block.source.utf8) else { throw MathAnalysisError.sourceMismatch }
        let offset = anchor.range.lowerBound
        func local(_ range: Range<Int>) -> Range<Int> {
            (range.lowerBound - offset) ..< (range.upperBound - offset)
        }
        let replacements = entries.map { entry in
            let range = entry.equation.syntax.fullRange
            return PreviewMathInput.Replacement(id: entry.id, range: local(range), expectedSource: original.substring(
                with: .init(location: range.lowerBound, length: range.count)
            ))
        }
        let repairs = try select(context.edits, range: anchor.range, originalRange: \.sourceRange).map { edit in
            PreviewMathInput.SourceEdit(range: local(edit.sourceRange), expectedSource: original.substring(
                with: .init(location: edit.sourceRange.lowerBound, length: edit.sourceRange.count)
            ), replacement: edit.replacement)
        }
        let selected = try references.references(for: anchor.range, sourceSHA256: anchor.sourceSHA256)
        var targets = selected.links.compactMap { link -> PreviewMathInput.Reference? in
            guard let destination = link.destination else { return nil }
            return .init(range: local(link.fullRange), destination: destination, kind: .link)
        }
        targets += selected.images.compactMap { image -> PreviewMathInput.Reference? in
            guard let source = image.source else { return nil }
            return .init(range: local(image.fullRange), destination: source, kind: .image)
        }
        let prefix = try references.prefix(for: anchor.range, sourceSHA256: anchor.sourceSHA256,
                                           maximumUTF8Bytes: PreviewParserBudget.maximumUTF8Bytes)
        return try PreviewMathInput(source: block.source, prefix: prefix, replacements: replacements,
                                    sourceEdits: repairs, references: targets)
    }

    private static func select<Item>(
        _ items: [Item], range: Range<Int>, originalRange: KeyPath<Item, Range<Int>>
    ) throws -> [Item] {
        var low = 0, high = items.count
        while low < high {
            let middle = low + (high - low) / 2
            if items[middle][keyPath: originalRange].upperBound <= range.lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let start = low
        while low < items.count, items[low][keyPath: originalRange].lowerBound < range.upperBound {
            let own = items[low][keyPath: originalRange]
            guard own.lowerBound >= range.lowerBound, own.upperBound <= range.upperBound else {
                throw MathAnalysisError.invalidPrefixMapping
            }
            low += 1
        }
        return Array(items[start ..< low])
    }

    private static func boundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1), current = source.character(at: offset)
        return !(previous == 13 && current == 10) &&
            !((0xD800 ... 0xDBFF).contains(previous) && (0xDC00 ... 0xDFFF).contains(current))
    }
}

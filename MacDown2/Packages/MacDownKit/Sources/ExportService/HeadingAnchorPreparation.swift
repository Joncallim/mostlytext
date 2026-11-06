import Foundation
import MarkdownEngine

/// A source-owned index shared by native Preview and static export. This value
/// proves source/emitted-heading agreement, not final contributed-HTML targets:
/// the exporter must still validate its accepted splices before publishing links.
public struct HeadingAnchorPreparation: Sendable, Equatable {
    public enum Failure: Error, Equatable {
        case sourceBudgetExceeded
        case headingBudgetExceeded
        case sourceMismatch
        case unverifiableMarkup
    }

    private struct Lifetime {
        let id: String
        let epoch: UUID
        let generation: UInt
    }

    /// Feature-local admission; ordinary rendering does not acquire this cap.
    public static let maximumHeadingCount = 16384

    public let index: HeadingAnchorIndex
    /// Exact decoded values, including distinct canonical Unicode spellings.
    public let authoredIdentifiers: [String]
    public let usedDOMAnalysis: Bool

    /// No resource URL is loaded or resolved. Synchronous cmark/DOM work stays
    /// off the caller's actor; the host must bound active and pending requests.
    @concurrent
    public static func prepare(
        document: MarkdownDocument, sourceText: String,
        documentID: String, recoveryEpoch: UUID, sourceGeneration: UInt
    ) async throws -> HeadingAnchorPreparation {
        try Task.checkCancellation()
        guard sourceText.utf8.count <= ExportResourceBudget.standard.maxSourceUTF8Bytes else {
            throw Failure.sourceBudgetExceeded
        }
        guard document.headings.count <= maximumHeadingCount else { throw Failure.headingBudgetExceeded }
        let lifetime = Lifetime(id: documentID, epoch: recoveryEpoch, generation: sourceGeneration)
        let baseline = try makeIndex(document: document, sourceText: sourceText, lifetime: lifetime, reservedIDs: [])
        // Escaped markup and code are conservative extra work below. Without
        // any literal '<', cmark cannot emit an authored HTML identifier.
        let needsMarkupAnalysis = !document.headings.isEmpty && document.body.utf8.contains(0x3C)
        try Task.checkCancellation()
        guard needsMarkupAnalysis else {
            return .init(index: baseline, authoredIdentifiers: [], usedDOMAnalysis: false)
        }
        let rendered = try CMarkGFM.render(
            document.body, options: CMarkGFM.optUnsafe | CMarkGFM.optSmart, headingAnalysis: .marked
        )
        try Task.checkCancellation()
        guard rendered.containsRawHTML else {
            return .init(index: baseline, authoredIdentifiers: [], usedDOMAnalysis: false)
        }
        guard let inspected = EmittedHeadingDOM.inspect(rendered) else { throw Failure.unverifiableMarkup }
        try Task.checkCancellation()
        let index = try makeIndex(
            document: document, sourceText: sourceText, lifetime: lifetime, reservedIDs: inspected.reservedIDs
        )
        let derived = DerivedContentComposer.compose(
            bodyText: document.body, bodyStartOffset: sourceText.utf16.count - document.body.utf16.count,
            sourceUTF16Length: sourceText.utf16.count, contributions: [], sourceGeneration: sourceGeneration,
            recordCoordinates: true
        )
        try Task.checkCancellation()
        guard let matches = EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: sourceText, derived: derived, rendered: rendered
        ), EmittedHeadingDOM.publish(inspected: inspected, rendered: rendered, matches: matches) != nil else {
            throw Failure.unverifiableMarkup
        }
        try Task.checkCancellation()
        return .init(index: index, authoredIdentifiers: inspected.reservedIDs, usedDOMAnalysis: true)
    }

    private static func makeIndex(
        document: MarkdownDocument, sourceText: String,
        lifetime: Lifetime, reservedIDs: [String]
    ) throws -> HeadingAnchorIndex {
        do {
            return try HeadingAnchorIndex(
                document: document, sourceText: sourceText, documentID: lifetime.id,
                recoveryEpoch: lifetime.epoch, sourceGeneration: lifetime.generation, reservedIDs: reservedIDs
            )
        } catch {
            throw Failure.sourceMismatch
        }
    }
}

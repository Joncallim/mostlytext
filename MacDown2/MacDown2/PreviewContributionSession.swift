import Contributions
import Foundation
import MarkdownEngine
import Preview

/// Identifies one `.task(id:)` cycle for Preview's contribution
/// composition: a document/tab identity plus the parsed revision it is
/// composing for. Two cycles with the same identity and revision are the
/// same logical unit of work even if unrelated `FileDocument` state (dirty,
/// save, URL, encoding) changed in between (architecture takeover, pass
/// 1/10).
struct PreviewContributionTaskID: Hashable {
    let documentIdentity: UUID
    let parsedRevision: Int?
    let headingBindingID: UUID?

    init(documentIdentity: UUID, parsedRevision: Int?, headingBindingID: UUID? = nil) {
        self.documentIdentity = documentIdentity
        self.parsedRevision = parsedRevision
        self.headingBindingID = headingBindingID
    }
}

/// Owns Preview's one atomic `PreviewContributionComposition` and the
/// task-ID guard that keeps a superseded/cancelled refresh from ever
/// publishing (architecture pass 1/10, 8/10). A plain `@Observable` class,
/// directly constructible and testable without hosting a SwiftUI view —
/// mirrors `MarkdownParseSession`'s own shape.
@MainActor
@Observable
final class PreviewContributionSession {
    private(set) var composition: PreviewContributionComposition = .empty
    private(set) var headingBindingID: UUID?
    private var currentTaskID: PreviewContributionTaskID?

    /// Runs the contribution registry and composes `baseBlocks` for one
    /// document snapshot. Only the call whose `taskID` is still current at
    /// each checkpoint may publish — an older, still-running call that has
    /// been superseded by a newer `refresh` performs no state mutation at
    /// all, matching Swift's cooperative-cancellation convention that
    /// cancellation is control flow, never a result.
    func refresh(
        taskID: PreviewContributionTaskID,
        document: MarkdownDocument,
        text: String,
        baseBlocks: [PreviewBlock],
        headingState: PreviewContributionAdapter.HeadingState? = nil
    ) async {
        guard !Task.isCancelled else { return }
        currentTaskID = taskID
        guard let sourceGeneration = UInt(exactly: document.revision) else {
            publishIfCurrent(taskID: taskID, invalidRevisionComposition(document.revision))
            return
        }

        do {
            let results = try await PreviewContributionAdapter.results(
                document: document, text: text, generation: sourceGeneration, headingState: headingState
            )
            try Task.checkCancellation()
            let composed = PreviewContributionAdapter.compose(
                base: baseBlocks, document: document, sourceText: text,
                contributions: results, sourceGeneration: sourceGeneration
            )
            try Task.checkCancellation()
            publishIfCurrent(taskID: taskID, composed)
        } catch is CancellationError {
            // A cancelled/superseded task publishes nothing.
        } catch {
            let diagnostic = PreviewContributionDiagnostic(
                contributionID: "preview", severity: .error, message: error.localizedDescription
            )
            publishIfCurrent(taskID: taskID, PreviewContributionComposition(
                sourceGeneration: sourceGeneration, blocks: nil, diagnostics: [diagnostic]
            ))
        }
    }

    /// The blocks Preview should actually render right now.
    func displayedBlocks(baseBlocks: [PreviewBlock]?, currentRevision: Int?) -> [PreviewBlock]? {
        PreviewCompositionDisplay.blocks(
            composition: composition,
            baseBlocks: baseBlocks,
            currentRevision: currentRevision
        )
    }

    /// The diagnostics Preview should actually show right now.
    func displayedDiagnostics(currentRevision: Int?) -> [PreviewContributionDiagnostic] {
        PreviewCompositionDisplay.diagnostics(composition: composition, currentRevision: currentRevision)
    }

    private func publishIfCurrent(taskID: PreviewContributionTaskID, _ composition: PreviewContributionComposition) {
        guard currentTaskID == taskID else { return }
        self.composition = composition
        headingBindingID = taskID.headingBindingID
    }

    /// `Int -> UInt` only fails for a negative revision, which
    /// `MarkdownParseSession`'s monotonically increasing counter never
    /// produces — kept as an explicit, never-silently-wrapped diagnostic
    /// path rather than an assumed invariant.
    private func invalidRevisionComposition(_ revision: Int) -> PreviewContributionComposition {
        let diagnostic = PreviewContributionDiagnostic(
            contributionID: "preview", severity: .error,
            message: String(localized: "parsed revision \(revision) could not be represented; contributions skipped")
        )
        return PreviewContributionComposition(sourceGeneration: nil, blocks: nil, diagnostics: [diagnostic])
    }
}

/// Pure display-gating rules, split out so they are testable without an
/// `@Observable` session: composed content is shown only when its token
/// matches the revision currently on screen; otherwise the caller's
/// synchronous base blocks are shown and diagnostics are hidden rather than
/// risking a stale display (architecture pass 1/10).
enum PreviewCompositionDisplay {
    static func isCurrent(_ composition: PreviewContributionComposition, forRevision revision: Int?) -> Bool {
        guard let revision, let token = UInt(exactly: revision) else { return false }
        return composition.sourceGeneration == token
    }

    static func blocks(
        composition: PreviewContributionComposition,
        baseBlocks: [PreviewBlock]?,
        currentRevision: Int?
    ) -> [PreviewBlock]? {
        guard isCurrent(composition, forRevision: currentRevision) else { return baseBlocks }
        return composition.blocks ?? baseBlocks
    }

    static func diagnostics(
        composition: PreviewContributionComposition,
        currentRevision: Int?
    ) -> [PreviewContributionDiagnostic] {
        isCurrent(composition, forRevision: currentRevision) ? composition.diagnostics : []
    }
}

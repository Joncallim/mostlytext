import Contributions
import Foundation
import MarkdownEngine
import Preview

/// One diagnostic surfaced by Preview's contribution composition — either
/// forwarded from a contribution's own `ContributionDiagnostic`, or raised by
/// the adapter itself when a result cannot be admitted (architecture
/// takeover, pass 9/10).
struct PreviewContributionDiagnostic: Sendable, Equatable {
    let contributionID: String
    let severity: ContributionDiagnostic.Severity
    let message: String
}

/// One atomic snapshot of Preview's derived-content state. `blocks == nil`
/// means "nothing has been composed yet" (the initial/reset state); an empty
/// or unchanged `base` array composed successfully is a real, non-nil value.
/// Published as a single unit so a cancelled/superseded task can never
/// publish half of one and none of the other (architecture pass 1/10, 8/10).
struct PreviewContributionComposition: Sendable, Equatable {
    let sourceGeneration: UInt?
    let blocks: [PreviewBlock]?
    let diagnostics: [PreviewContributionDiagnostic]

    static let empty = PreviewContributionComposition(sourceGeneration: nil, blocks: nil, diagnostics: [])
}

/// Preview's own resource ceiling — deliberately smaller than, and
/// independent of, `ExportResourceBudget`; the two are not required to move
/// together (architecture pass 7/10).
struct PreviewContributionBudget: Sendable, Equatable {
    let maximumAcceptedPlacements: Int
    let maximumGeneratedMarkdownUTF8Bytes: Int

    static let standard = PreviewContributionBudget(
        maximumAcceptedPlacements: 64,
        maximumGeneratedMarkdownUTF8Bytes: 64 * 1024
    )
}

/// The fixed inputs shared by every candidate's admission check in one
/// `compose` call — grouped so admission functions take one parameter
/// instead of re-threading six independent ones.
struct PreviewCompositionContext {
    let base: [PreviewBlock]
    let baseIntervals: [Range<Int>]
    let document: MarkdownDocument
    let sourceText: String
    let sourceUTF16Length: Int
    let sourceGeneration: UInt
    let locale: Locale
}

/// One structurally valid placement, ready for overlap/budget resolution and
/// then composition. Carries everything the composer needs so it never has
/// to re-derive placement rules from the original `ContributionResult`.
struct PreviewContributionCandidate {
    let resultIndex: Int
    let contributionID: String
    let sourceRange: Range<Int>
    let placement: ContributionPlacement
    let markdown: String
    let containingBlockIndex: Int
}

/// One piece of an affected block's rebuilt content: either the block's own
/// authored text (optionally with inline splices folded in) or one
/// contribution's generated Markdown.
struct PreviewContributionFragment {
    enum Role: String {
        case authored
        case inlineComposed = "inline-composed"
        case generated
    }

    let role: Role
    let text: String
    let range: Range<Int>
    let contributionID: String?
}

/// The outcome of running one `ContributionResult` through the admission
/// pipeline.
enum PreviewAdmissionOutcome {
    /// No content to place, or a producer-reported `.error` diagnostic
    /// already explains why — no separate adapter diagnostic is added.
    case skipped
    case accepted(PreviewContributionCandidate)
    /// Content existed but could not be admitted; `String` is the adapter
    /// diagnostic message (source preservation is implied and stated).
    case rejected(String)
}

import Foundation

/// Whether a derived contribution occupies an inline run of text (E19 math) or
/// a whole block (E20 diagrams). The two shapes cannot be mixed: a block
/// contribution replaces a block-level authored range, an inline contribution
/// replaces a run inside a single paragraph.
public enum ExportDerivedPlacement: Sendable, Equatable {
    case inline
    case block
}

/// A renderer-neutral derived-content contribution that E12 can place into an
/// export without knowing which feature produced it.
///
/// E14/E19/E20 later supply instances of this type; E12 never calls a math or
/// diagram renderer. `html` must be a self-contained fragment (no external
/// fetches) so first-party export stays local and offline.
public struct ExportDerivedContribution: Sendable, Equatable {
    /// UTF-16 offsets into the ORIGINAL source this contribution replaces.
    /// Anchored to the authored text, not to cmark source positions, so a
    /// renderer that reads the editor snapshot can contribute without knowing
    /// anything about E12's parse pipeline.
    public let sourceRange: Range<Int>

    /// Inline or block placement.
    public let placement: ExportDerivedPlacement

    /// The self-contained HTML fragment to place at `sourceRange`.
    public let html: String

    /// The `FileDocument.mutationGeneration` the contribution was computed
    /// from. Used to reject stale contributions when the export snapshot has
    /// moved on.
    public let sourceGeneration: UInt

    /// Renderer diagnostics, if any. A contribution may still be placed when it
    /// carries only warnings; an error-level diagnostic accompanies a
    /// contribution that must be treated as failed by the composer.
    public let diagnostics: [ExportDiagnostic]

    /// Feature intent that only tightens failure behavior. It grants no target
    /// or resource authority: the shared preparation and final checks still do.
    public let requiresHeadingNavigation: Bool

    public init(
        sourceRange: Range<Int>,
        placement: ExportDerivedPlacement,
        html: String,
        sourceGeneration: UInt,
        diagnostics: [ExportDiagnostic] = [],
        requiresHeadingNavigation: Bool = false
    ) {
        self.sourceRange = sourceRange
        self.placement = placement
        self.html = html
        self.sourceGeneration = sourceGeneration
        self.diagnostics = diagnostics
        self.requiresHeadingNavigation = requiresHeadingNavigation
    }
}

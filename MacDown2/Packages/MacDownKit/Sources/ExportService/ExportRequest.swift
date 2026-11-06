import Foundation
import MarkdownEngine
import Themes

/// A self-contained export request: the live editor snapshot plus the inputs
/// the composer needs. Resource authority is an explicit retained capability;
/// layout, budget, metadata policy and template remain composer-owned.
public struct ExportRequest: Sendable, Equatable {
    /// The full document text as it exists in the editor at export time.
    public let text: String

    /// `FileDocument.mutationGeneration` of the snapshot. Kept as `UInt` here;
    /// the exact `Int` conversion happens only at the `ParseExecuting` call.
    public let sourceGeneration: UInt

    /// The preview/export theme. Supplies the CSS variable block.
    public let theme: Theme

    /// The exact editor Markdown parse settings captured for this export.
    /// Existing callers retain the standard behavior unless they opt in.
    public let parseOptions: MarkdownParseOptions

    /// The saved document's own file URL, or `nil` for an untitled document.
    ///
    /// This is metadata, including the browser-title fallback. It grants no
    /// authority to read siblings: relative images require `resourceAccess`.
    public let documentURL: URL?

    /// An explicitly admitted directory retained for this operation. Nil means
    /// no local-resource access, even when a saved document URL is present.
    public let resourceAccess: ExportResourceAccess?
    /// Previously observed source identity used only for overwrite refusal.
    public let protectedSourceIdentity: ExportProtectedFileIdentity?

    /// Renderer-neutral derived-content contributions (E19 inline math,
    /// E20 block diagrams) that this export must place. Empty for ordinary
    /// Markdown.
    public let contributions: [ExportDerivedContribution]

    /// Opt-in generated targets from the same source/parse snapshot. The final
    /// composer verifies accepted splices and emitted headings before resolving
    /// resource slots. Nil preserves ordinary export's existing path and limits.
    public let headingPreparation: HeadingAnchorPreparation?

    public var headingIndex: HeadingAnchorIndex? {
        headingPreparation?.index
    }

    public init(
        text: String,
        sourceGeneration: UInt,
        theme: Theme,
        documentURL: URL? = nil,
        resourceAccess: ExportResourceAccess? = nil,
        protectedSourceIdentity: ExportProtectedFileIdentity? = nil,
        parseOptions: MarkdownParseOptions = .default,
        contributions: [ExportDerivedContribution] = [],
        headingPreparation: HeadingAnchorPreparation? = nil
    ) {
        self.text = text
        self.sourceGeneration = sourceGeneration
        self.theme = theme
        self.parseOptions = parseOptions
        self.documentURL = documentURL
        self.resourceAccess = resourceAccess
        self.protectedSourceIdentity = protectedSourceIdentity
        self.contributions = contributions
        self.headingPreparation = headingPreparation
    }

    /// The saved filename without its extension, used only as the browser-title
    /// fallback when front matter carries no usable title.
    var fileNameStem: String? {
        guard let stem = documentURL?.deletingPathExtension().lastPathComponent, !stem.isEmpty else {
            return nil
        }
        return stem
    }
}

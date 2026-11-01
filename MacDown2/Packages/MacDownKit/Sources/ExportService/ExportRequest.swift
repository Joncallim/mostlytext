import Foundation
import MarkdownEngine
import Themes

/// A self-contained export request: the live editor snapshot plus the inputs
/// the composer needs. No layout, resource-root, budget, metadata-policy, or
/// template identity may be supplied — those are fixed by the composer.
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
    /// One URL is the single source of truth for two derived facts: the
    /// resource root (its parent directory) and the browser-title fallback (its
    /// filename stem). Neither may be supplied separately, so they cannot
    /// disagree.
    public let documentURL: URL?

    /// Renderer-neutral derived-content contributions (E19 inline math,
    /// E20 block diagrams) that this export must place. Empty for ordinary
    /// Markdown.
    public let contributions: [ExportDerivedContribution]

    public init(
        text: String,
        sourceGeneration: UInt,
        theme: Theme,
        documentURL: URL? = nil,
        parseOptions: MarkdownParseOptions = .default,
        contributions: [ExportDerivedContribution] = []
    ) {
        self.text = text
        self.sourceGeneration = sourceGeneration
        self.theme = theme
        self.parseOptions = parseOptions
        self.documentURL = documentURL
        self.contributions = contributions
    }

    /// The directory relative resource references resolve against. An untitled
    /// document has no root: E12 never guesses the process working directory.
    var documentDirectory: URL? {
        documentURL?.deletingLastPathComponent()
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

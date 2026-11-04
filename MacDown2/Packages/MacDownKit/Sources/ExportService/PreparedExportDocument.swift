import CryptoKit
import Foundation

/// The frozen result of export composition: everything needed to render HTML or
/// feed the PDF adapter, with no further composition decisions left to make.
///
/// `bodyHTML` is the cmark-rendered body fragment. Resource references in it
/// have already been rewritten to their content-addressed companion form
/// (`<assetsDirectoryName>/<64hex>.<ext>`); the HTML writers either keep that
/// form (companion output) or embed the bytes as data URIs (self-contained/PDF).
public struct PreparedExportDocument: Sendable, Equatable {
    /// The browser title: front matter's `title`, else the saved filename stem,
    /// else empty (in which case no `<title>` element is emitted).
    public let title: String

    /// The heading rendered at the top of the document. Present only when front
    /// matter supplied a title AND the body does not already open with its own
    /// heading; a filename fallback is never a visible heading.
    public let visibleTitle: String?

    /// The rendered Markdown body, with derived content and resource references
    /// resolved to companion form.
    public let bodyHTML: String

    /// The companion directory name baked into every `<assetsDirectoryName>/…`
    /// reference in `bodyHTML`: the primary file's own basename, so exports
    /// sharing a folder never share a companion directory. Fixed at composition
    /// time (`ExportComposer`) because it must match exactly what was already
    /// written into the body — the HTML writers cannot choose a different name
    /// after the fact.
    public let assetsDirectoryName: String

    /// The combined stylesheet: structural CSS + the theme variable block.
    public let stylesheet: String

    /// The frozen resource manifest.
    public let manifest: ExportManifest

    /// Composition diagnostics (warnings and errors), never silently dropped.
    public let diagnostics: [ExportDiagnostic]

    /// The `FileDocument.mutationGeneration` of the source snapshot.
    public let sourceGeneration: UInt

    /// `true` when authored raw HTML was preserved (`CMARK_OPT_UNSAFE`).
    public let preservesRawHTML: Bool

    /// Only the composer can establish complete companion references. Public
    /// prepared values, including arbitrary body HTML or CSS, start unknown.
    private var closedReferenceSourceDigest: Data?

    var companionReferencesKnown: Bool {
        closedReferenceSourceDigest != nil
    }

    func certifyingCompanionReferences(sourceText: String) -> Self {
        var result = self
        result.closedReferenceSourceDigest = Data(SHA256.hash(data: Data(sourceText.utf8)))
        return result
    }

    func hasClosedCompanionReferences(for sourceText: String) -> Bool {
        closedReferenceSourceDigest == Data(SHA256.hash(data: Data(sourceText.utf8)))
    }

    private(set) var resourceSlots: ExportResourceSlots?

    func registeringResourceSlots(_ slots: ExportResourceSlots?) -> Self {
        var result = self
        result.resourceSlots = slots
        return result
    }

    public init(
        title: String,
        visibleTitle: String? = nil,
        bodyHTML: String,
        assetsDirectoryName: String = ExportHTMLWriter.defaultAssetsDirectoryName,
        stylesheet: String,
        manifest: ExportManifest,
        diagnostics: [ExportDiagnostic],
        sourceGeneration: UInt,
        preservesRawHTML: Bool
    ) {
        self.title = title
        self.visibleTitle = visibleTitle
        self.bodyHTML = bodyHTML
        self.assetsDirectoryName = assetsDirectoryName
        self.stylesheet = stylesheet
        self.manifest = manifest
        self.diagnostics = diagnostics
        self.sourceGeneration = sourceGeneration
        self.preservesRawHTML = preservesRawHTML
    }
}

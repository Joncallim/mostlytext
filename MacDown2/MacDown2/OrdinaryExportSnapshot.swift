import ExportService
import FileCore
import Foundation
import MarkdownEngine
import Themes

/// Immutable source and presentation inputs captured after the ordinary
/// export panel is accepted, before parsing or rendering can suspend.
struct OrdinaryExportSnapshot: Sendable, Equatable {
    let text: String
    let sourceGeneration: UInt
    let theme: Theme
    let documentURL: URL?
    let parseOptions: MarkdownParseOptions

    init(document: FileCore.FileDocument, theme: Theme, parseOptions: MarkdownParseOptions) {
        text = document.text
        sourceGeneration = document.mutationGeneration
        self.theme = theme
        documentURL = document.fileURL
        self.parseOptions = parseOptions
    }

    func request(contributions: [ExportDerivedContribution]) -> ExportRequest {
        ExportRequest(
            text: text,
            sourceGeneration: sourceGeneration,
            theme: theme,
            documentURL: documentURL,
            parseOptions: parseOptions,
            contributions: contributions
        )
    }
}

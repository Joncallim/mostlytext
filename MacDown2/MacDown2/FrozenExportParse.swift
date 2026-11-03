import ExportService
import MarkdownEngine

/// Reuses the one immutable Markdown parse for contribution generation and
/// composition. A different source, revision or parse policy cannot borrow it.
actor FrozenExportParse: ParseExecuting {
    let text: String
    let revision: Int
    private var document: MarkdownDocument?
    private let options: MarkdownParseOptions
    private let releaseAfterUse: Bool

    init(text: String, revision: Int, document: MarkdownDocument, options: MarkdownParseOptions = .default,
         releaseAfterUse: Bool = false) {
        self.text = text
        self.revision = revision
        self.document = document
        self.options = options
        self.releaseAfterUse = releaseAfterUse
    }

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        try Task.checkCancellation()
        guard let document, text.utf8.elementsEqual(self.text.utf8), revision == self.revision, options == self.options,
              document.revision == revision, document.options == options
        else { throw ExportError.invalidSourceSnapshot }
        if releaseAfterUse {
            self.document = nil
        }
        return document
    }
}

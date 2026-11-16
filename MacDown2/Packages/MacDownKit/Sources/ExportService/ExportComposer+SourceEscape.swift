import Foundation

extension ExportComposer {
    /// cmark's escaped output can cost far more memory than the authored UTF-8
    /// source. Count a conservative expansion allowance before building its
    /// tree or render buffer. The prepared and final byte gates still apply to
    /// the actual output; this early guard bounds the known escape-heavy path.
    static func checkSourceEscapeWork(_ source: String) throws {
        var potentialExtraBytes = 0
        for byte in source.utf8 {
            switch byte {
            case 38: potentialExtraBytes += 4 // &amp;
            case 60, 62: potentialExtraBytes += 3 // &lt; and &gt;
            case 34, 39: potentialExtraBytes += 5 // Conservative quoted forms.
            default: break
            }
            guard potentialExtraBytes <= ExportResourceBudget.maxPotentialHTMLEscapeExpansionBytes else {
                let limit = ExportResourceBudget.describe(
                    bytes: ExportResourceBudget.maxPotentialHTMLEscapeExpansionBytes
                )
                throw ExportError.budgetExceeded(
                    String(
                        localized: "the document contains too much text that expands during export (limit: \(limit))",
                        bundle: .module
                    )
                )
            }
        }
    }
}

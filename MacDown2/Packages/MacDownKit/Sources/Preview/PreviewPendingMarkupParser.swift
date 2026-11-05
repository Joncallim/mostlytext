import Foundation
import Textual

/// Pending authored blocks have no original URL authority yet. Generated
/// content and callers outside the source-owned app path keep their normal
/// parser; this value never introduces another dollar extension.
struct PreviewPendingMarkupParser: MarkupParser {
    let baseURL: URL?

    func attributedString(for source: String) throws -> AttributedString {
        do {
            let parsed = try AttributedStringMarkdownParser(
                baseURL: baseURL, options: .init(appliesSourcePositionAttributes: true), syntaxExtensions: []
            ).attributedString(for: source)
            guard parsed.runs.allSatisfy({ $0.link == nil && $0.imageURL == nil }) else {
                return AttributedString(source)
            }
            return parsed
        } catch {
            return AttributedString(source)
        }
    }
}

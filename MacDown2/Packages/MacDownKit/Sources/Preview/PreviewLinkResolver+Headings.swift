import Foundation
import MarkdownEngine

extension PreviewLinkResolver {
    static func headingAction(
        for url: URL, currentDocument: URL?, index: HeadingAnchorIndex?
    ) -> LinkAction? {
        guard let target = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let encoded = target.percentEncodedFragment else { return nil }
        let fragmentOnly = target.scheme == nil && target.host == nil && target.path.isEmpty && target.query == nil
        if !fragmentOnly {
            guard url.isFileURL, let currentDocument, currentDocument.isFileURL,
                  let current = URLComponents(url: currentDocument, resolvingAgainstBaseURL: true),
                  url.standardizedFileURL.path.utf8.elementsEqual(currentDocument.standardizedFileURL.path.utf8)
            else { return nil }
            // Same path with a different authority/query cannot borrow this
            // document's heading index. Never reopen it as an external fallback.
            guard target.host?.lowercased() == current.host?.lowercased(),
                  target.user == nil, target.password == nil, target.port == nil,
                  target.percentEncodedQuery == current.percentEncodedQuery else { return .ignore }
        }
        guard let decoded = encoded.removingPercentEncoding,
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return .ignore }
        // URLComponents.fragment already decodes escapes. Work from the encoded
        // field and decode exactly once so %2520 cannot become a different ID.
        guard let index, let heading = index.headings.first(where: { $0.fragment.utf8.elementsEqual(decoded.utf8) })
        else { return .unresolvedInternal(decoded) }
        return .internalHeading(heading, index.identity)
    }
}

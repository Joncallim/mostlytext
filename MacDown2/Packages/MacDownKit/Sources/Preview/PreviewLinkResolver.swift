import Foundation
import MarkdownEngine

/// Resolves links clicked in the preview.
///
/// Absolute URLs are returned unchanged. Relative URLs are resolved against the
/// document's base URL when one is available.
public struct PreviewLinkResolver: Sendable, Equatable {
    public let baseURL: URL?
    public let headingIndex: HeadingAnchorIndex?

    public init(baseURL: URL? = nil, headingIndex: HeadingAnchorIndex? = nil) {
        self.baseURL = baseURL
        self.headingIndex = headingIndex
    }

    /// Resolves `url` relative to the document base URL.
    ///
    /// Returns `url` unchanged when it is already absolute or when no base URL
    /// is set.
    public func resolve(_ url: URL) -> URL {
        guard url.scheme == nil || url.scheme?.isEmpty == true else {
            return url
        }
        guard let baseURL else { return url }
        return URL(string: url.absoluteString, relativeTo: baseURL)?.absoluteURL ?? url
    }

    /// What clicking a resolved Preview link may do. The document is untrusted
    /// (a downloaded README, say) and the app is not sandboxed, so handing every
    /// URL to Launch Services would let `[x](scripts/setup.command)`,
    /// `[x](file:///Applications/Foo.app)` or an `ssh:`/`vnc:`/`x-…:` handler run
    /// something on a click.
    public enum LinkAction: Sendable, Equatable {
        /// Hand to the default handler: web pages and mail.
        case open
        /// Open one of the user's own text documents in MostlyText.
        case openInApp(URL)
        /// Show a local file in Finder without opening or executing it.
        case reveal
        /// The host must revalidate its source/parser/window binding on press.
        case internalHeading(HeadingAnchorIndex.Heading, HeadingAnchorIdentity)
        /// Native Preview cannot display every authored raw-HTML target.
        case unresolvedInternal(String)
        /// Do nothing.
        case ignore
    }

    static let openableDocumentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt", "text"]

    /// `currentDocument` is the document being previewed: a same-document
    /// `#anchor` link resolves to that file plus a fragment, and must not reopen it.
    public static func action(
        for url: URL, currentDocument: URL? = nil, headingIndex: HeadingAnchorIndex? = nil
    ) -> LinkAction {
        if let action = headingAction(for: url, currentDocument: currentDocument, index: headingIndex) {
            return action
        }
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .open
        case "file":
            guard openableDocumentExtensions.contains(url.pathExtension.lowercased()) else { return .reveal }
            var target = url
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.fragment = nil
                components.query = nil
                target = components.url ?? url
            }
            if let currentDocument,
               target.standardizedFileURL.path == currentDocument.standardizedFileURL.path {
                return .ignore
            }
            return .openInApp(target)
        default:
            return .ignore
        }
    }
}

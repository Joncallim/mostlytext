import Foundation

/// Restricts harness navigation to actual descendants of its bundled resource directory.
/// A textual path prefix also matches a sibling such as `Resources-extra`.
public enum DiagramNavigationPolicy {
    /// A WebKit page may load scripts and WASM from its bundled directory, but
    /// only the one selected harness may replace the top-level document.
    public static func allowsHarnessNavigation(_ requestedURL: URL?, harnessURL: URL) -> Bool {
        requestedURL == harnessURL
    }

    public static func allows(_ requestedURL: URL?, within allowedDirectory: URL) -> Bool {
        guard let requestedURL,
              requestedURL.isFileURL, requestedURL.host == nil,
              allowedDirectory.isFileURL, allowedDirectory.host == nil else {
            return false
        }
        let root = allowedDirectory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let requested = requestedURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return requested.count > root.count && requested.starts(with: root)
    }
}

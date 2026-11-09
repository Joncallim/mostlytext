import FileCore
import Foundation

// MARK: - Policy

/// The v1 scripts-disabled security policy for the read-only HTML preview
/// (EPIC-11 Gate 4).
///
/// `Preview` owns the *policy* — the app-owned `WKWebView` host in
/// `DocumentEditorSplitView` enforces it. The v1 policy disables content
/// JavaScript, blocks every network fetch, denies external navigation, popups,
/// and downloads, and allows subresources only from the approved document
/// directory (see `HTMLPreviewResourceScope`).
public struct HTMLPreviewPolicy: Sendable, Equatable {
    /// Content JavaScript (`WKWebViewConfiguration.defaultWebpagePreferences.allowsContentJavaScript`).
    public var allowsContentJavaScript: Bool
    /// Content-Security-Policy injected into every hardened document.
    public var contentSecurityPolicy: String
    /// Any network fetch (`http`, `https`, `ws`, …) from the previewed document.
    public var allowsNetworkAccess: Bool
    /// Navigations to any URL outside the preview's own scheme.
    public var allowsExternalNavigation: Bool
    /// `window.open` / `target="_blank"` popups.
    public var allowsPopups: Bool
    /// Downloads (content-disposition attachments or non-renderable MIME types).
    public var allowsDownloads: Bool
    /// File access outside the approved document resource root.
    public var allowsResourceAccessOutsideDocumentRoot: Bool

    // `v1` is the plan's versioned policy name (see EPIC-11 Gate 4); the
    // two-letter identifier is deliberate and matches the plan's wording.
    // swiftlint:disable:next identifier_name
    public static let v1 = HTMLPreviewPolicy(
        allowsContentJavaScript: false,
        contentSecurityPolicy: PreviewSecurity.contentSecurityPolicy,
        allowsNetworkAccess: false,
        allowsExternalNavigation: false,
        allowsPopups: false,
        allowsDownloads: false,
        allowsResourceAccessOutsideDocumentRoot: false
    )
}

// MARK: - Response headers

/// Response headers the preview host attaches when serving preview resources.
///
/// The authoritative Content-Security-Policy travels as a response header,
/// not only as the injected `<meta>` tag in `PreviewSecurity`. A
/// `meta http-equiv="Content-Security-Policy"` only applies when the injector
/// places it in the *real* head, and a string scanner cannot know the real
/// head: `<template>` contents, `<select>`/`<table>` insertion modes, foreign
/// content (`<svg>`, `<math>`), and implied-head cases can all make a
/// scanner-visible `<head>` dead context, silently disabling the injected
/// policy. WebKit honors CSP headers on custom-scheme responses, and no
/// document markup can divert a header — so the header is the enforcement
/// boundary and the meta injection is belt-and-braces.
public enum HTMLPreviewResponseHeaders {
    /// The CSP response header name.
    public static let contentSecurityPolicy = "Content-Security-Policy"

    /// The hardening headers for a served preview resource. The CSP governs
    /// any document the response renders as (HTML, SVG, XML) and is ignored
    /// by non-document payloads (images, fonts, media), so it is attached to
    /// every response without per-MIME branching.
    public static func hardeningHeaders(for policy: HTMLPreviewPolicy) -> [String: String] {
        [contentSecurityPolicy: policy.contentSecurityPolicy]
    }

    /// `hardeningHeaders` plus the `Content-Type` every response needs (see `HTMLPreviewContentType`).
    public static func headers(for policy: HTMLPreviewPolicy, contentType: String) -> [String: String] {
        var headers = hardeningHeaders(for: policy)
        headers["Content-Type"] = contentType
        return headers
    }
}

// MARK: - Request

/// A typed request to render a saved HTML source revision in the preview.
///
/// Requests are immutable snapshots. The app host issues one request per
/// *saved* document generation (reload-on-save); the `HTMLPreviewReloadGate`
/// — not the request — owns generation tracking and decides whether a request
/// supersedes the currently loaded revision.
public struct HTMLPreviewRequest: Sendable, Equatable {
    /// The saved source text, unmodified.
    public let source: String
    /// The approved document directory for relative subresources, or `nil`
    /// when the document is untitled and has no local resource root.
    public let baseURL: URL?
    /// The policy in effect while rendering this request.
    public let policy: HTMLPreviewPolicy

    public init(
        source: String,
        baseURL: URL?,
        policy: HTMLPreviewPolicy = .v1
    ) {
        self.source = source
        self.baseURL = baseURL
        self.policy = policy
    }
}

// MARK: - Resource scope

/// Validates subresource access against an approved document directory.
///
/// A previewed HTML document may load relative resources (images, stylesheets,
/// fonts, media) only from the directory of the document that was opened.
/// Everything else — remote URLs, `javascript:` URLs, `../` escapes, absolute
/// paths outside the root, and symlinks resolving outside the root — is
/// rejected. Untitled documents have no resource root and approve nothing.
///
/// This path-only helper remains for policy compatibility checks. Its result
/// must not be reopened as authority: a filesystem object can change after
/// validation. The active app scheme handler uses a pinned directory
/// descriptor and `ContainedResourceReader` for the actual resource bytes.
public enum HTMLPreviewResourceScope {
    /// Returns the approved `file:` URL for `resourceURL`, or `nil` when the
    /// resource must not be served.
    ///
    /// - `resourceURL`: the URL of the requested subresource (already resolved
    ///   against the document base).
    /// - `rootURL`: the approved document directory, or `nil` for untitled
    ///   documents (nothing is approved).
    public static func approvedFileURL(for resourceURL: URL, relativeTo rootURL: URL?) -> URL? {
        guard let rootURL else { return nil }

        guard resourceURL.isFileURL else { return nil }

        // The requested file must live under the root *after* resolving `..`,
        // `.`, and symlinks: a symlink inside the root pointing outside it is
        // an escape, not an approved resource.
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = resourceURL.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(candidate, in: root) else { return nil }

        // Directories are not resources.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }
        return candidate
    }

    /// Whether `candidate` is `root` itself or a descendant, comparing
    /// path components so `root-other` never matches `root`.
    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy(==)
    }
}

// MARK: - Navigation policy

/// The delegate-facing description of a navigation attempt inside the preview.
///
/// WebKit types cannot live in this module; the app host translates
/// `WKNavigationAction` into this value and consults
/// `HTMLPreviewNavigationPolicy` for the decision.
public struct HTMLPreviewNavigationAction: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case mainFrame
        case subframe
        case newWindow
    }

    public let url: URL?
    /// A same-document navigation (fragment anchor) — no document leaves the
    /// preview.
    public let isSameDocument: Bool
    public let target: Target

    public init(url: URL?, isSameDocument: Bool, target: Target) {
        self.url = url
        self.isSameDocument = isSameDocument
        self.target = target
    }
}

public enum HTMLPreviewNavigationDecision: Sendable, Equatable {
    case allow
    case cancel
}

/// The v1 navigation rule set for the preview web view.
///
/// - Same-document (fragment) navigations are allowed.
/// - The preview's own scheme (`macdown-preview://…`) is the only navigable
///   scheme. It exists solely inside this web view; every request is validated
///   by the scheme handler before any bytes are served, and every `text/html`
///   payload the handler serves is re-hardened with the preview CSP.
/// - Everything else — remote URLs, `file:` URLs, `javascript:` URLs, `data:`
///   replacements (which would drop the hardened CSP), form submissions, link
///   clicks, and popup windows — is cancelled.
public enum HTMLPreviewNavigationPolicy {
    public static let previewURLScheme = "macdown-preview"

    public static func decision(
        for action: HTMLPreviewNavigationAction,
        policy: HTMLPreviewPolicy
    ) -> HTMLPreviewNavigationDecision {
        guard policy.allowsExternalNavigation else {
            if action.isSameDocument {
                return .allow
            }
            if action.target == .newWindow {
                return policy.allowsPopups ? .allow : .cancel
            }
            return urlAllowsNavigation(action.url, policy: policy) ? .allow : .cancel
        }
        return .allow
    }

    private static func urlAllowsNavigation(_ url: URL?, policy: HTMLPreviewPolicy) -> Bool {
        guard let url else { return false }
        let scheme = url.scheme?.lowercased()
        if scheme == previewURLScheme {
            return true
        }
        if scheme == "file", policy.allowsResourceAccessOutsideDocumentRoot {
            return true
        }
        if ["http", "https", "ws", "wss", "ftp"].contains(scheme) {
            return policy.allowsNetworkAccess
        }
        return false
    }
}

// MARK: - Reload gate

/// Latest-request-wins generation gate for preview reloads (EPIC-11 Gate 4).
///
/// The app host calls `shouldLoad(generation:)` for every candidate request —
/// one per *saved* document generation, issued by `updateNSView` — and only
/// starts a WebKit load for approved generations. Unrelated SwiftUI updates
/// re-issue the same generation and are rejected; an edit that lands between a
/// load start and its completion never overwrites a newer pending load.
///
/// The gate is intentionally free of WebKit types so the reload contract is
/// unit-testable (`HTMLPreviewReloadGenerationTests`).
public struct HTMLPreviewReloadGate: Sendable, Equatable {
    public private(set) var lastLoadedGeneration: UInt?
    public private(set) var pendingGeneration: UInt?

    public init() {}

    /// Registers `generation` as the latest candidate. Returns `true` when the
    /// caller should start a load for it, `false` when it is stale (older than
    /// a load that already completed) or a duplicate of the pending request.
    public mutating func shouldLoad(generation: UInt) -> Bool {
        let latest = max(lastLoadedGeneration ?? 0, pendingGeneration ?? 0)
        guard generation > latest else { return false }
        pendingGeneration = generation
        return true
    }

    /// Records that the load for `generation` finished (successfully or not).
    /// A completion for a superseded generation is ignored so a cancelled
    /// in-flight load can never become the "loaded" revision.
    public mutating func loadCompleted(generation: UInt) {
        guard pendingGeneration == generation else { return }
        lastLoadedGeneration = generation
        pendingGeneration = nil
    }

    /// Records that the load for `generation` failed without rendering.
    ///
    /// Unlike a completed load, a failure is *not* recorded as the loaded
    /// revision: the same generation may be re-issued. A failure for a
    /// superseded generation is ignored so an interrupted older load can
    /// never re-arm a newer pending load.
    public mutating func loadFailed(generation: UInt) {
        guard pendingGeneration == generation else { return }
        pendingGeneration = nil
    }

    /// Drops any pending load without completing it (disposal, supersede).
    public mutating func cancelPendingLoad() {
        pendingGeneration = nil
    }
}

import Diagrams
import DiagramWebKitPool
import Foundation
import WebKit

/// Only the navigation returned by this page's own harness load may make it ready.
@MainActor
final class MermaidHarnessNavigationCompletion {
    private var navigation: WKNavigation?
    private var continuation: CheckedContinuation<Void, any Error>?

    var isPending: Bool {
        continuation != nil
    }

    func begin(_ continuation: CheckedContinuation<Void, any Error>, start: () -> WKNavigation?) {
        guard self.continuation == nil else {
            continuation.resume(throwing: MermaidRenderError.rendererUnavailable)
            return
        }
        self.continuation = continuation
        guard let navigation = start() else {
            complete(.failure(MermaidRenderError.rendererUnavailable))
            return
        }
        self.navigation = navigation
    }

    func finish(for callback: WKNavigation?, with result: Result<Void, any Error>) {
        guard let navigation, let callback, navigation === callback else { return }
        complete(result)
    }

    func terminate(with error: any Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Void, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        navigation = nil
        continuation.resume(with: result)
    }
}

/// One offscreen, never-displayed page hosting the bundled Mermaid harness
/// (epic-20-implementation.md §10). Owns exactly one `WKWebView`, loaded
/// once and reused across many `render(_:)` calls by its owning pool slot
/// (`MermaidWebRenderer`).
///
/// Security containment, all independently applied (§10 — layered, not any
/// one relied on alone):
/// - `websiteDataStore = .nonPersistent()`: no cookies/storage survive.
/// - `loadFileURL(_:allowingReadAccessTo:)` scoped exactly to the bundled
///   resource directory: the page can read only its own harness files, not
///   the wider file system. Network requests are blocked by the harness CSP.
/// - A `WKNavigationDelegate` that cancels any navigation whose destination
///   is not inside that same directory — Mermaid's own rendering call never
///   navigates anywhere; this guards against a hypothetical bug or a future
///   Mermaid version doing so.
/// - A `WKUIDelegate` that denies any popup/new-window request.
/// - The harness page's own Content-Security-Policy (`harness.html`)
///   additionally blocks any network `fetch`/`XHR`/`WebSocket`
///   (`connect-src 'none'`) even if executed script attempted one.
/// - Mermaid's own `securityLevel: 'strict'` configuration (`render.js`)
///   disables `click` interaction directives and sanitizes HTML in labels,
///   so the *output* SVG never carries script-bearing content regardless of
///   how a later consumer treats it.
@MainActor
final class MermaidHarnessPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let allowedDirectory: URL
    private let harnessURL: URL
    private let loadCompletion = MermaidHarnessNavigationCompletion()

    /// The WebContent process died; the renderer replaces a terminated page instead of reusing it.
    private(set) var isTerminated = false

    /// `NSObject` does not permit an `async`/`throws` designated
    /// initializer (it would override `NSObject.init()`'s plain,
    /// synchronous signature), so construction is split: this factory
    /// resolves the bundled harness and performs the async page load,
    /// while `init(harnessURL:)` stays a normal, synchronous
    /// designated initializer.
    static func make() async throws -> MermaidHarnessPage {
        guard let harnessURL = Bundle.module.url(forResource: "harness", withExtension: "html") else {
            throw MermaidRenderError.rendererUnavailable
        }
        let page = MermaidHarnessPage(harnessURL: harnessURL)
        do {
            try await page.load(harnessURL: harnessURL)
            return page
        } catch {
            page.teardown()
            throw error
        }
    }

    private init(harnessURL: URL) {
        self.harnessURL = harnessURL
        allowedDirectory = harnessURL.deletingLastPathComponent()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    private func load(harnessURL: URL) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !isTerminated else {
                    continuation.resume(throwing: MermaidRenderError.rendererUnavailable)
                    return
                }
                loadCompletion.begin(continuation) {
                    webView.loadFileURL(harnessURL, allowingReadAccessTo: allowedDirectory)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.teardown() }
        }
    }

    /// Calls into the harness's `window.__macdownRenderMermaid` and
    /// interprets its plain, JSON-shaped result (`render.js`'s own doc
    /// comment). Uses `callAsyncJavaScript`, which is purpose-built for a
    /// promise-returning body and binds `source` as an argument rather than
    /// interpolating it into evaluated script text — so diagram text
    /// containing quotes, backslashes, or newlines can never break out of a
    /// string literal, because there is no string literal to break out of.
    func render(_ source: String, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        let result = try await webView.callAsyncJavaScript(
            "return await window.__macdownRenderMermaid(source, theme, maxOutputBytes);",
            arguments: [
                "source": source,
                "theme": context.palette.rendererArguments,
                "maxOutputBytes": MermaidWebRenderer.defaultMaxOutputBytes,
            ],
            in: nil,
            contentWorld: .page
        )
        guard let dict = result as? [String: Any], let succeeded = dict["ok"] as? Bool else {
            throw MermaidRenderError.rendererUnavailable
        }
        if let byteCount = (dict["outputTooLargeByteCount"] as? NSNumber)?.intValue {
            throw MermaidRenderError.outputTooLarge(byteCount: byteCount)
        }
        guard succeeded else {
            throw MermaidWebRenderer.failure(for: dict["message"] as? String)
        }
        guard let svg = dict["svg"] as? String else {
            throw MermaidRenderError.rendererUnavailable
        }
        // A `png` decode failure is intentionally not fatal to the whole
        // render: `svg` (Export's only consumer) is still perfectly valid.
        // Only native Preview display loses its snapshot in that case.
        let pngData = (dict["png"] as? String).flatMap { Data(base64Encoded: $0) }
        let width = (dict["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (dict["height"] as? NSNumber)?.doubleValue ?? 0
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw MermaidRenderError.rendererUnavailable
        }
        return RenderedMermaidDiagram(svg: svg, pngData: pngData, naturalWidth: width, naturalHeight: height)
    }

    /// Runs the same real WebKit canvas path as production rendering against
    /// a supplied SVG. Package tests use this to cover valid SVG dimension
    /// forms that Mermaid's normal output does not currently generate.
    func inspectSVGCanvasForTesting(_ svg: String) async throws -> [String: Any] {
        let result = try await webView.callAsyncJavaScript(
            "return await window.__macdownInspectMermaidSVG(svg);",
            arguments: ["svg": svg],
            in: nil,
            contentWorld: .page
        )
        guard let dict = result as? [String: Any] else {
            throw MermaidRenderError.rendererUnavailable
        }
        return dict
    }

    /// Checks the production raster admission without allocating a large canvas.
    func inspectRasterSizeForTesting(width: Double, height: Double) async throws -> [String: Any] {
        let result = try await webView.callAsyncJavaScript(
            "return checkedRasterSize(width, height);",
            arguments: ["width": width, "height": height],
            in: nil,
            contentWorld: .page
        )
        guard let dict = result as? [String: Any] else {
            throw MermaidRenderError.rendererUnavailable
        }
        return dict
    }

    func teardown() {
        isTerminated = true
        loadCompletion.terminate(with: MermaidRenderError.rendererUnavailable)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    // MARK: - WKNavigationDelegate

    func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        loadCompletion.finish(for: navigation, with: .success(()))
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        isTerminated = true
        loadCompletion.terminate(with: MermaidRenderError.timedOut)
    }

    func webView(_: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadCompletion.finish(for: navigation, with: .failure(error))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadCompletion.finish(for: navigation, with: .failure(error))
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard DiagramNavigationPolicy.allowsHarnessNavigation(
            navigationAction.request.url, harnessURL: harnessURL
        ) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

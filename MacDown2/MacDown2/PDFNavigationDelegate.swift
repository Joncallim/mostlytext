import Foundation
import WebKit

/// Bridges the PDF print view's callback-based load to an async continuation.
/// WebKit invokes its navigation delegate on the main actor.
@MainActor
final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private weak var loadingView: WKWebView?

    func load(_ html: String, in webView: WKWebView, timeout: Duration) async throws {
        // WebKit can stall without delivering a delegate failure. Keep a fixed
        // deadline independent of the cancellation path below.
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resume(PDFExportAdapter.PDFExportError.pageLoadTimedOut)
        }
        defer { watchdog.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                loadingView = webView
                guard !Task.isCancelled else {
                    cancel()
                    return
                }
                webView.loadHTMLString(html, baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    private func cancel() {
        let view = loadingView
        resume(CancellationError())
        // A synchronous WebKit failure callback must not replace the
        // cancellation result while the load is being stopped.
        view?.stopLoading()
    }

    /// The string-loaded `about:blank` page is the only permitted navigation.
    /// CSP controls subresources, not authored meta-refresh navigation.
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(PDFNavigationPolicy.allows(navigationAction.request.url) ? .allow : .cancel)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        resume(nil)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        resume(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        resume(error)
    }

    private func resume(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        loadingView = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

/// Which navigations the PDF print web view may perform.
enum PDFNavigationPolicy {
    /// Only the string-loaded document itself (`loadHTMLString(_, baseURL: nil)` navigates to `about:blank`).
    static func allows(_ url: URL?) -> Bool {
        guard let url else { return true }
        return url.absoluteString == "about:blank"
    }
}

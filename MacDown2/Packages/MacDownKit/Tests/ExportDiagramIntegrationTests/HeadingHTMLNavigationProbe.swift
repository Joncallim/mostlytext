import Foundation
import Testing
import WebKit

/// A newly created WKWebView's initial empty document is already complete.
/// Wait for the specific load, rather than mistaking that document for Export.
@MainActor
final class HeadingHTMLNavigationProbe: NSObject, WKNavigationDelegate {
    private var expected: WKNavigation?
    private var finished = false
    private var failure: (any Error)?

    static func load(_ html: String, in view: WKWebView) async throws {
        let probe = HeadingHTMLNavigationProbe()
        view.navigationDelegate = probe
        defer { view.navigationDelegate = nil }
        probe.expected = try #require(view.loadHTMLString(html, baseURL: nil))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !probe.finished, probe.failure == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if let failure = probe.failure {
            throw failure
        }
        try #require(probe.finished, "The exact exported-HTML navigation must finish within its original deadline")
    }

    func webView(_: WKWebView, didFinish navigation: WKNavigation?) {
        guard let expected, navigation === expected else { return }
        finished = true
    }

    func webView(_: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        guard let expected, navigation === expected else { return }
        failure = error
    }

    func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        guard let expected, navigation === expected else { return }
        failure = error
    }
}

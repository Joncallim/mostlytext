import Foundation
import OSLog
import QuickLookSource
import QuickLookUI
import WebKit

/// The first production Quick Look slice publishes only a passive source view.
/// Derived rendering remains behind the bounded-worker acceptance gate.
final class MarkdownQuickLookProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let selectedURL = request.fileURL
        let selected = try await QuickLookSelectedFileOpener.open(selectedURL)
        let minimalPageLoaded = await ExtensionWebKitProbe().run()
        Logger(subsystem: "app.mostlytext.quicklook.worker", category: "extension-probe")
            .notice("Minimal extension WebKit page loaded: \(minimalPageLoaded)")
        guard let html = await QuickLookWorkerClient.renderSource(selected) else {
            throw QuickLookSourceError.readFailed
        }
        try Task.checkCancellation()
        let payload = Payload(html: html)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            payload.html
        }
        reply.stringEncoding = .utf8
        return reply
    }

    private final class Payload: Sendable {
        let html: Data

        init(html: Data) {
            self.html = html
        }
    }
}

/// Temporary process-placement probe; this branch is not a product candidate.
@MainActor
private final class ExtensionWebKitProbe: NSObject, WKNavigationDelegate {
    private let logger = Logger(subsystem: "app.mostlytext.quicklook.worker", category: "extension-probe")
    private var view: WKWebView?
    private var pending: CheckedContinuation<Bool, Never>?

    func run() async -> Bool {
        logger.notice("Minimal extension WebKit construction entered")
        let configuration = WKWebViewConfiguration()
        logger.notice("Minimal extension WebKit configuration constructed")
        configuration.websiteDataStore = .nonPersistent()
        logger.notice("Minimal extension WebKit data store assigned")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        logger.notice("Minimal extension WebKit view constructed")
        view = webView
        webView.navigationDelegate = self
        return await withCheckedContinuation { continuation in
            pending = continuation
            _ = webView.loadHTMLString("<!doctype html><html><body>EXTENSION_MINIMAL_PROBE</body></html>", baseURL: nil)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if self.pending != nil {
                    self.logger.error("Minimal extension WebKit page timed out")
                    self.finish(false)
                }
            }
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        finish(true)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        logger.error("Minimal extension WebContent process terminated")
        finish(false)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        logger.error("Minimal extension WebKit navigation failed: \(String(describing: error))")
        finish(false)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        logger.error("Minimal extension WebKit provisional navigation failed: \(String(describing: error))")
        finish(false)
    }

    private func finish(_ loaded: Bool) {
        guard let pending else { return }
        self.pending = nil
        view?.navigationDelegate = nil
        view?.stopLoading()
        view = nil
        pending.resume(returning: loaded)
    }
}

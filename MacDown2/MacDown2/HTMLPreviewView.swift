import FileCore
import Preview
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private struct HTMLPreviewLoadIdentity {
    let documentID: String
    let recoveryEpoch: UUID
    let generation: UInt
}

// MARK: - HTML preview host

/// App-owned host for the hardened HTML preview (EPIC-11 Gate 4).
///
/// The v1 policy (`HTMLPreviewPolicy.v1`) is enforced here:
/// - Content JavaScript is disabled at the web-view configuration level and
///   no script bridge exists.
/// - The document loads through the `macdown-preview:` custom scheme, so
///   `file:` URLs never reach the web view. The scheme handler
///   (`PreviewSchemeHandler`) serves the main document and reads subresources
///   beneath the saved load's pinned directory descriptor. Escaping paths and
///   symlink replacements are refused. Every response carries the authoritative
///   CSP header
///   (`HTMLPreviewResponseHeaders`), which no markup can divert; `text/html`
///   payloads are additionally re-hardened with the meta CSP injection as
///   belt-and-braces.
/// - `WKNavigationDelegate` cancels every navigation outside the preview
///   scheme (remote URLs, `javascript:` links, `data:` replacements, meta
///   refreshes) and cancels download-only responses; `WKUIDelegate` denies
///   popups outright.
/// - Reloads are latest-request-wins (`HTMLPreviewReloadGate`), debounced,
///   and fire only for *saved* (clean) document generations — unrelated
///   SwiftUI updates never restart WebKit. A failed main-document load
///   re-arms the gate so the same generation can be retried.
struct HTMLPreviewView: NSViewRepresentable {
    private struct PendingNavigation {
        let navigation: WKNavigation
        let webViewID: ObjectIdentifier
        let generation: UInt
        let mainURL: URL
    }

    let document: FileCore.FileDocument

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.preview(document: document, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dispose(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let reloadDelay: Duration
        private let handler = PreviewSchemeHandler()
        private(set) var gate = HTMLPreviewReloadGate()
        private var reloadBudget = HTMLPreviewReloadBudget()
        private var reloadTask: Task<Void, Never>?
        private var scheduledLoadID: UUID?
        private var pendingNavigation: PendingNavigation?
        private var currentPageGeneration: UInt?
        private weak var currentWebView: WKWebView?

        init(reloadDelay: Duration = .milliseconds(150)) {
            self.reloadDelay = reloadDelay
            super.init()
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            // v1 policy: content JavaScript off for every navigation. The
            // deprecated `preferences.javaScriptEnabled` is intentionally not
            // used; `defaultWebpagePreferences` is the macOS 11+ replacement.
            // The value reads from the policy so the two cannot drift.
            configuration.defaultWebpagePreferences.allowsContentJavaScript =
                HTMLPreviewPolicy.v1.allowsContentJavaScript
            // No cookies or storage survive between previews.
            configuration.websiteDataStore = .nonPersistent()
            // Every document resource flows through the validated scheme.
            configuration.setURLSchemeHandler(
                handler,
                forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
            )

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            return webView
        }

        /// Evaluates the current saved revision and starts a debounced,
        /// generation-gated reload. Called on every SwiftUI update; the gate
        /// guarantees unrelated updates cause zero reloads.
        func preview(document: FileCore.FileDocument, in webView: WKWebView) {
            guard document.state == .clean else {
                reloadTask?.cancel()
                reloadTask = nil
                scheduledLoadID = nil
                return
            }
            let generation = document.mutationGeneration
            guard gate.shouldLoad(generation: generation) else { return }

            reloadTask?.cancel()
            let loadID = UUID()
            scheduledLoadID = loadID
            let source = document.text
            let documentURL = document.fileURL
            let baseURL = documentURL?.deletingLastPathComponent()
            let identity = HTMLPreviewLoadIdentity(
                documentID: document.id,
                recoveryEpoch: document.recoveryEpoch,
                generation: generation
            )
            let delay = reloadDelay
            reloadTask = Task { @MainActor [weak self, weak webView] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self, let webView, !Task.isCancelled, scheduledLoadID == loadID else { return }
                scheduledLoadID = nil
                reloadTask = nil
                beginLoad(
                    source: source,
                    documentURL: documentURL,
                    baseURL: baseURL,
                    identity: identity,
                    in: webView
                )
            }
        }

        func dispose(webView: WKWebView) {
            reloadTask?.cancel()
            reloadTask = nil
            scheduledLoadID = nil
            gate.cancelPendingLoad()
            pendingNavigation = nil
            currentPageGeneration = nil
            currentWebView = nil
            handler.retire()
            webView.stopLoading()
        }

        // MARK: Loads

        private func beginLoad(
            source: String,
            documentURL: URL?,
            baseURL: URL?,
            identity: HTMLPreviewLoadIdentity,
            in webView: WKWebView
        ) {
            // Revoke the old delegate identity before WebKit can report its cancellation.
            pendingNavigation = nil
            currentPageGeneration = identity.generation
            currentWebView = webView
            let previewURL = handler.install(
                HTMLPreviewRequest(source: source, baseURL: baseURL, policy: .v1),
                documentURL: documentURL,
                documentID: identity.documentID,
                recoveryEpoch: identity.recoveryEpoch,
                generation: identity.generation
            )
            // A genuinely new document (not the process-termination reload): its crashes are a new story.
            reloadBudget.documentChanged()

            // The main document loads *through the scheme handler* (not via
            // `loadHTMLString`) so the authoritative CSP response header
            // (`HTMLPreviewResponseHeaders`) covers it. A meta-injected CSP
            // alone can land in dead markup (`<template>`, `<select>`, …) and
            // silently do nothing; a response header cannot be diverted.
            guard let previewURL else {
                gate.loadFailed(generation: identity.generation)
                return
            }
            recordNavigation(
                webView.load(URLRequest(url: previewURL)), generation: identity.generation,
                mainURL: previewURL, in: webView
            )
        }

        private func recordNavigation(
            _ navigation: WKNavigation?, generation: UInt, mainURL: URL, in webView: WKWebView
        ) {
            guard let navigation else {
                // Only this attempt may be rearmed; a newer debounced request owns its own admission.
                gate.loadFailed(generation: generation)
                return
            }
            pendingNavigation = PendingNavigation(
                navigation: navigation, webViewID: ObjectIdentifier(webView),
                generation: generation, mainURL: mainURL
            )
        }

        private func takePendingNavigation(
            for navigation: WKNavigation?, in webView: WKWebView
        ) -> PendingNavigation? {
            guard let navigation, let pendingNavigation,
                  pendingNavigation.navigation === navigation,
                  pendingNavigation.webViewID == ObjectIdentifier(webView)
            else { return nil }
            self.pendingNavigation = nil
            return pendingNavigation
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // A nil targetFrame means a new-window request (`target="_blank"`,
            // `window.open`): classify it as `.newWindow` so the policy's
            // popup denial applies at the navigation layer too, not only via
            // `createWebViewWith`.
            let target: HTMLPreviewNavigationAction.Target = if let frame = navigationAction.targetFrame {
                frame.isMainFrame ? .mainFrame : .subframe
            } else {
                .newWindow
            }
            let action = HTMLPreviewNavigationAction(
                url: navigationAction.request.url,
                isSameDocument: isSameDocumentNavigation(navigationAction, in: webView),
                target: target
            )
            let decision = HTMLPreviewNavigationPolicy.decision(for: action, policy: .v1)
            decisionHandler(decision == .allow ? .allow : .cancel)
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            // Download denial is a response-layer decision governed by the
            // active request's policy: anything the preview cannot render
            // inline is cancelled rather than offered to the file system.
            let allowsDownloads = handler.request?.policy.allowsDownloads ?? HTMLPreviewPolicy.v1.allowsDownloads
            if !allowsDownloads, !navigationResponse.canShowMIMEType {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let pending = takePendingNavigation(for: navigation, in: webView) else { return }
            gate.loadCompleted(generation: pending.generation)
        }

        /// The WebContent process died (memory pressure, a crash on a huge page): the pane would stay blank
        /// until the next save. The scheme handler still holds the request, so reload it.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard webView === currentWebView, handler.request != nil,
                  scheduledLoadID == nil,
                  let generation = currentPageGeneration,
                  let mainURL = handler.mainURL,
                  reloadBudget.consumeReload()
            else { return }
            // A queued load owns its admission even when it retries this page's generation.
            // Recovery has its own navigation identity and never borrows that admission.
            pendingNavigation = nil
            recordNavigation(webView.reload(), generation: generation, mainURL: mainURL, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleLoadFailure(error, navigation: navigation, in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(error, navigation: navigation, in: webView)
        }

        /// A failed main-document load re-arms the gate so the same saved
        /// generation can be retried on the next update. Cancelled and
        /// superseded loads are ignored (they are not failures), and only the
        /// main document URL may fail the gate: a subframe failure must never
        /// clear a still-pending main load.
        private func handleLoadFailure(_ error: Error, navigation: WKNavigation?, in webView: WKWebView) {
            guard let expectedURL = pendingNavigation?.mainURL,
                  Self.isMainDocumentLoadFailure(error, expectedURL: expectedURL),
                  let pending = takePendingNavigation(for: navigation, in: webView)
            else { return }
            gate.loadFailed(generation: pending.generation)
        }

        static func isMainDocumentLoadFailure(_ error: Error, expectedURL: URL) -> Bool {
            let nsError = error as NSError
            // -999 (NSURLErrorCancelled, incl. policy cancels) and 102
            // (WebKitErrorFrameLoadInterruptedByPolicyChange, supersede) are
            // not failures of the pending load.
            guard nsError.code != NSURLErrorCancelled, nsError.code != 102 else { return false }
            guard let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL else { return false }
            return failingURL == expectedURL
        }

        // MARK: WKUIDelegate

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for _: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            // v1 policy denies popups outright.
            nil
        }

        // MARK: Helpers

        /// A fragment navigation within the currently loaded preview page.
        private func isSameDocumentNavigation(
            _ action: WKNavigationAction,
            in webView: WKWebView
        ) -> Bool {
            guard let requestURL = action.request.url, let currentURL = webView.url else { return false }
            return withoutFragment(requestURL) == withoutFragment(currentURL)
        }

        private func withoutFragment(_ url: URL) -> String {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            components.fragment = nil
            return components.string ?? url.absoluteString
        }
    }
}

import FileCore
import Preview
import SwiftUI
import WebKit

private struct SecuredHTMLIdentity: Equatable {
    let tabID: UUID
    let documentID: String
    let recoveryEpoch: UUID
    let fileURL: URL?
    let savedGeneration: UInt
    let grantRevision: UUID

    func sameDocument(as other: Self) -> Bool {
        tabID == other.tabID && documentID == other.documentID
            && recoveryEpoch == other.recoveryEpoch && fileURL == other.fileURL
            && grantRevision == other.grantRevision
    }
}

private struct SecuredHTMLPage {
    let identity: SecuredHTMLIdentity
    let load: BoundedHTMLPreviewLoad
    let handler: BoundedHTMLPreviewHandler
    let webView: WKWebView
    let token: PreviewResourceLoad?
    var pendingNavigation: WKNavigation?
    var crashReloads = 0
}

/// Saved-HTML preview. Each accepted render replaces its child WKWebView, configuration and immutable scheme
/// handler. Local subresources require this document window's explicit, still-current folder attachment.
struct SecuredHTMLPreviewView: NSViewRepresentable {
    let document: FileCore.FileDocument
    let tabID: UUID

    @Environment(\.previewResourceWindowState) private var owner

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ host: NSView, context: Context) {
        context.coordinator.update(host: host, document: document, tabID: tabID, owner: owner)
    }

    static func dismantleNSView(_ host: NSView, coordinator: Coordinator) {
        coordinator.dispose(host: host)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var page: SecuredHTMLPage?
        private var scheduled: SecuredHTMLIdentity?
        private var reloadTask: Task<Void, Never>?
        private var disposed = false

        func update(host: NSView, document: FileCore.FileDocument,
                    tabID: UUID, owner: PreviewResourceWindowState?) {
            guard !disposed else { return }
            let identity = SecuredHTMLIdentity(
                tabID: tabID, documentID: document.id, recoveryEpoch: document.recoveryEpoch,
                fileURL: document.fileURL, savedGeneration: document.mutationGeneration,
                grantRevision: owner?.revision ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            )
            if let page, !page.identity.sameDocument(as: identity) {
                retireCurrent(owner: owner)
            }
            guard document.state == .clean else {
                cancelScheduled()
                return
            }
            guard page?.identity != identity, scheduled != identity else { return }
            cancelScheduled()
            scheduled = identity
            let source = document.text
            reloadTask = Task { @MainActor [weak self, weak host, weak owner] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, let host, !Task.isCancelled, scheduled == identity else { return }
                scheduled = nil
                reloadTask = nil
                begin(identity: identity, document: document, source: source, host: host, owner: owner)
            }
        }

        func dispose(host: NSView) {
            guard !disposed else { return }
            disposed = true
            cancelScheduled()
            retireCurrent(owner: nil)
            host.subviews.forEach { $0.removeFromSuperview() }
        }

        private func begin(identity: SecuredHTMLIdentity, document: FileCore.FileDocument,
                           source: String, host: NSView, owner: PreviewResourceWindowState?) {
            guard !disposed else { return }
            // The owner reads its current window model before replacing the old HTML token. A delayed task for
            // a same-text Save As or prior source generation cannot retire the newer page.
            guard let owner, owner.isCurrentPreview(
                document, tabID: identity.tabID,
                sourceGeneration: identity.savedGeneration, grantRevision: identity.grantRevision
            ) else { return }
            let token = owner.beginPreviewLoad(
                for: document, tabID: identity.tabID,
                sourceGeneration: identity.savedGeneration,
                grantRevision: identity.grantRevision, consumer: .html
            )
            guard owner.revision == identity.grantRevision else { return }
            retireCurrent(owner: owner)
            host.subviews.forEach { $0.removeFromSuperview() }
            do {
                let load = try BoundedHTMLPreviewLoad(document: document, source: source, grant: token)
                let handler = BoundedHTMLPreviewHandler(load: load)
                let configuration = WKWebViewConfiguration()
                configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                configuration.websiteDataStore = .nonPersistent()
                configuration.setURLSchemeHandler(
                    handler, forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
                )
                let webView = WKWebView(frame: host.bounds, configuration: configuration)
                webView.autoresizingMask = [.width, .height]
                webView.navigationDelegate = self
                webView.uiDelegate = self
                host.addSubview(webView)
                page = SecuredHTMLPage(identity: identity, load: load, handler: handler,
                                       webView: webView, token: token)
                guard let navigation = webView.load(URLRequest(url: load.mainURL)) else {
                    failDirectLoad(in: webView)
                    return
                }
                page?.pendingNavigation = navigation
            } catch {
                if let token {
                    owner.retire(.html, matching: token)
                }
                showFailure(in: host)
            }
        }

        private func cancelScheduled() {
            reloadTask?.cancel()
            reloadTask = nil
            scheduled = nil
        }

        private func retireCurrent(owner: PreviewResourceWindowState?) {
            guard let old = page else { return }
            page = nil
            old.handler.dispose()
            old.webView.stopLoading()
            old.webView.navigationDelegate = nil
            old.webView.uiDelegate = nil
            old.webView.removeFromSuperview()
            if let token = old.token {
                owner?.retire(.html, matching: token)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let page, page.webView === webView else { decisionHandler(.cancel); return }
            let target: HTMLPreviewNavigationAction.Target = if let frame = action.targetFrame {
                frame.isMainFrame ? .mainFrame : .subframe
            } else {
                .newWindow
            }
            let requestURL = action.request.url
            let sameDocument = if let requestURL, let currentURL = webView.url {
                strippedFragment(requestURL) == strippedFragment(currentURL)
            } else {
                false
            }
            let decision = HTMLPreviewNavigationPolicy.decision(
                for: HTMLPreviewNavigationAction(url: requestURL, isSameDocument: sameDocument, target: target),
                policy: page.load.policy
            )
            let sameAuthority = requestURL?.scheme == HTMLPreviewNavigationPolicy.previewURLScheme
                && requestURL?.host == page.load.authority
            decisionHandler(decision == .allow && sameAuthority ? .allow : .cancel)
        }

        func webView(_: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard page?.webView === webView, page?.pendingNavigation === navigation else { return }
            page?.pendingNavigation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleLoadFailure(error, navigation: navigation, in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(error, navigation: navigation, in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard page?.webView === webView, page?.crashReloads == 0,
                  scheduled == nil else { return }
            page?.crashReloads += 1
            guard let navigation = webView.reload() else {
                failDirectLoad(in: webView)
                return
            }
            page?.pendingNavigation = navigation
        }

        private func handleLoadFailure(_ error: Error, navigation: WKNavigation?, in webView: WKWebView) {
            guard let page, page.webView === webView,
                  let navigation, let pending = page.pendingNavigation, pending === navigation
            else { return }
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled, nsError.code != 102,
                  let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
                  failingURL == page.load.mainURL else { return }
            failDirectLoad(in: webView)
        }

        private func failDirectLoad(in webView: WKWebView) {
            guard page?.webView === webView else { return }
            let host = webView.superview
            retireCurrent(owner: nil)
            if let host {
                showFailure(in: host)
            }
        }

        private func showFailure(in host: NSView) {
            host.subviews.forEach { $0.removeFromSuperview() }
            let explanation = NSTextField(labelWithString: String(localized:
                "HTML preview unavailable for this document. Switch to Source to read it."))
            explanation.frame = host.bounds.insetBy(dx: 16, dy: 16)
            explanation.autoresizingMask = [.width, .height]
            explanation.lineBreakMode = .byWordWrapping
            host.addSubview(explanation)
        }

        func webView(_: WKWebView, createWebViewWith _: WKWebViewConfiguration,
                     for _: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
            nil
        }

        private func strippedFragment(_ url: URL?) -> String? {
            guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            components.fragment = nil
            return components.string
        }
    }
}

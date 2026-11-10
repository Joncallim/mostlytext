import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Preview
import Testing
import WebKit

/// Uses a temporary in-memory document and no folder grant or permission prompt. WebKit must request the main
/// document from the immutable handler; direct fake-scheme-task tests cannot establish that routing.
@Suite("Secured HTML native routing", .serialized)
@MainActor
struct SecuredHTMLPreviewNativeTests {
    @Test func savedRevisionsReplaceTheWebViewAndDeliverTheirOwnMainBytes() async throws {
        let tabID = UUID()
        var document = FileDocument(text: "<html><head><title>Preview A</title></head><body>A</body></html>")
        let owner = PreviewResourceWindowState()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let coordinator = SecuredHTMLPreviewView.Coordinator()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let window = NSWindow(
            contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            coordinator.dispose(host: host)
            owner.close()
            window.orderOut(nil)
        }

        coordinator.update(host: host, document: document, tabID: tabID, owner: owner)
        let first = try await waitForPage(title: "Preview A", in: host)
        let firstHandler = try #require(first.configuration.urlSchemeHandler(
            forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
        ) as? BoundedHTMLPreviewHandler)
        #expect(first.url == firstHandler.load.mainURL)
        #expect(String(data: firstHandler.load.mainData, encoding: .utf8)?.contains("Preview A") == true)
        assertResponsePolicy(coordinator, current: first, currentURL: firstHandler.load.mainURL)

        document = document.updatingText("<html><head><title>Preview B</title></head><body>B</body></html>")
            .markClean()
        coordinator.update(host: host, document: document, tabID: tabID, owner: owner)
        let second = try await waitForPage(title: "Preview B", in: host)
        let secondHandler = try #require(second.configuration.urlSchemeHandler(
            forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
        ) as? BoundedHTMLPreviewHandler)
        #expect(second !== first)
        #expect(secondHandler.load.authority != firstHandler.load.authority)
        #expect(second.url == secondHandler.load.mainURL)
        assertResponsePolicy(
            coordinator, current: second, currentURL: secondHandler.load.mainURL,
            stale: first, staleURL: firstHandler.load.mainURL
        )
        coordinator.dispose(host: host)
        #expect(coordinator.responsePolicy(
            for: second, url: secondHandler.load.mainURL, canShowMIMEType: true
        ) == .cancel)
    }

    private func assertResponsePolicy(
        _ coordinator: SecuredHTMLPreviewView.Coordinator, current: WKWebView, currentURL: URL,
        stale: WKWebView? = nil, staleURL: URL? = nil
    ) {
        #expect(coordinator.responsePolicy(for: current, url: currentURL, canShowMIMEType: true) == .allow)
        #expect(coordinator.responsePolicy(
            for: current, url: currentURL.appendingPathComponent("local.svg"), canShowMIMEType: true
        ) == .allow)
        #expect(coordinator.responsePolicy(for: current, url: currentURL, canShowMIMEType: false) == .cancel)
        #expect(coordinator.responsePolicy(for: current, url: nil, canShowMIMEType: true) == .cancel)
        #expect(coordinator.responsePolicy(
            for: current, url: URL(string: "https://example.invalid/"), canShowMIMEType: true
        ) == .cancel)
        var userInfoURL = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
        userInfoURL?.user = "forged"
        #expect(userInfoURL?.url != nil)
        #expect(coordinator.responsePolicy(
            for: current, url: userInfoURL?.url, canShowMIMEType: true
        ) == .cancel)
        var portURL = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
        portURL?.port = 443
        #expect(portURL?.url != nil)
        #expect(coordinator.responsePolicy(for: current, url: portURL?.url, canShowMIMEType: true) == .cancel)
        if let stale, let staleURL {
            #expect(coordinator.responsePolicy(for: stale, url: staleURL, canShowMIMEType: true) == .cancel)
            #expect(coordinator.responsePolicy(for: current, url: staleURL, canShowMIMEType: true) == .cancel)
        }
    }

    private func waitForPage(title: String, in host: NSView) async throws -> WKWebView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let view = host.subviews.compactMap({ $0 as? WKWebView }).first,
               view.title == title {
                return view
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Native WebKit did not finish the expected immutable saved render: \(title)")
        throw BoundedHTMLPreviewError.denied
    }
}

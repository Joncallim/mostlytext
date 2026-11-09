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

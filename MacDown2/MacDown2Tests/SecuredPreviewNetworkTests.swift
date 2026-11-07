import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing
import WebKit

/// The opt-in hosted harness owns an actual loopback listener. A positive HTTP control prevents a dead listener
/// from being mistaken for WebKit containment. Ordinary full CI keeps this external-fixture suite disabled.
@Suite("Secured Preview observed network denial", .enabled(if:
    ProcessInfo.processInfo.environment["MOSTLYTEXT_PREVIEW_TRIPWIRE"] != nil))
@MainActor
struct SecuredPreviewNetworkTests {
    @Test func hostileResourcesCannotReachAnIndependentlyWorkingHTTPListener() async throws {
        let address = try #require(ProcessInfo.processInfo.environment["MOSTLYTEXT_PREVIEW_TRIPWIRE"])
        let base = try #require(URL(string: address))
        let (control, response) = try await URLSession.shared.data(from: base.appendingPathComponent("control"))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: control, encoding: .utf8) == "control-live")
        try await assertOrdinaryWebKitCanReachListener(base)
        let document = FileDocument(text: hostileSource(address: address))
        let tabID = UUID()
        let owner = PreviewResourceWindowState()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let coordinator = SecuredHTMLPreviewView.Coordinator()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            coordinator.dispose(host: host)
            owner.close()
            window.orderOut(nil)
        }
        coordinator.update(host: host, document: document, tabID: tabID, owner: owner)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var loaded = false
        while ContinuousClock.now < deadline {
            if let webView = host.subviews.compactMap({ $0 as? WKWebView }).first,
               webView.title == "Contained fixture", !webView.isLoading {
                loaded = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(loaded, "The real immutable WebKit page must finish before observing denied requests")
        try await Task.sleep(for: .seconds(1))
        let (status, _) = try await URLSession.shared.data(from: base.appendingPathComponent("status"))
        let paths = try #require(JSONSerialization.jsonObject(with: status) as? [String])
        #expect(paths.contains("/control"))
        #expect(paths.contains("/control-webkit"))
        let denied = paths.filter { $0.hasPrefix("/denied/") }
        #expect(denied.isEmpty)
        print("PREVIEW_NETWORK_CONTROL live=true loaded=\(loaded) deniedRequests=\(denied.count)")
    }

    private func assertOrdinaryWebKitCanReachListener(_ base: URL) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let control = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200), configuration: configuration)
        let target = base.appendingPathComponent("control-webkit")
        _ = try #require(control.load(URLRequest(url: target)))
        defer { control.stopLoading() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if control.url == target, !control.isLoading {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The ordinary WebKit positive control did not reach the live listener")
    }

    private func hostileSource(address: String) -> String {
        """
        <html><head><title>Contained fixture</title>
        <link rel="stylesheet" href="\(address)/denied/style.css">
        <style>@import url('\(address)/denied/import.css');
        @font-face {font-family:tripwire;src:url('\(address)/denied/font.woff2')}
        body {background:url('\(address)/denied/background.png');font-family:tripwire}</style>
        </head><body>
        <img src="\(address)/denied/image.png">
        <img srcset="\(address)/denied/srcset.png 1x">
        <video autoplay src="\(address)/denied/video.mp4" poster="\(address)/denied/poster.png"></video>
        <audio autoplay src="\(address)/denied/audio.mp3"></audio>
        <iframe src="\(address)/denied/frame"></iframe>
        <object data="\(address)/denied/object"></object>
        <embed src="\(address)/denied/embed">
        <script src="\(address)/denied/script.js"></script>
        <script>fetch('\(address)/denied/fetch');window.open('\(address)/denied/popup')</script>
        </body></html>
        """
    }
}

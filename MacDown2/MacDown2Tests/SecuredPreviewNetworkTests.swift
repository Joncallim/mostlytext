import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Preview
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
        let (directory, document) = try makeSavedHostileDocument(address: address)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tabID = UUID()
        let owner = PreviewResourceWindowState()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let origin = try #require(owner.beginSelection(for: document))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: directory
        ))
        try await owner.install(selection, from: origin) { document }
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
        let webView = try await waitForPage(in: host)
        try await assertLocalControls(in: webView)
        try await assertNavigationControls(in: webView, host: host, base: base, localFile: documentURL)
        try await Task.sleep(for: .seconds(1))
        let (status, _) = try await URLSession.shared.data(from: base.appendingPathComponent("status"))
        let paths = try #require(JSONSerialization.jsonObject(with: status) as? [String])
        #expect(paths.contains("/control"))
        #expect(paths.contains("/control-webkit"))
        let denied = paths.filter { $0.hasPrefix("/denied/") }
        #expect(denied.isEmpty)
        print("PREVIEW_NETWORK_CONTROL live=true loaded=true deniedRequests=\(denied.count) local=true")
    }

    private func makeSavedHostileDocument(address: String) throws -> (URL, FileDocument) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("local.png"))
        try ".proof { color: rgb(12, 34, 56); }".write(
            to: directory.appendingPathComponent("local.css"), atomically: true, encoding: .utf8
        )
        let documentURL = directory.appendingPathComponent("hostile.html")
        try hostileSource(address: address).write(to: documentURL, atomically: true, encoding: .utf8)
        return try (directory, FileDocument(fileURL: documentURL).load())
    }

    private func waitForPage(in host: NSView) async throws -> WKWebView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let webView = host.subviews.compactMap({ $0 as? WKWebView }).first,
               webView.title == "Contained fixture", !webView.isLoading {
                return webView
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The real immutable WebKit page did not finish before observing denied requests")
        throw BoundedHTMLPreviewError.denied
    }

    private func assertLocalControls(in webView: WKWebView) async throws {
        let handler = try #require(webView.configuration.urlSchemeHandler(
            forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
        ) as? BoundedHTMLPreviewHandler)
        #expect(webView.url == handler.load.mainURL)
        let localReadback = try await webView.evaluateJavaScript("""
        [document.getElementById('local')?.naturalWidth ?? -1,
         getComputedStyle(document.getElementById('proof')).color,
         typeof window.previewScriptRan].join('|')
        """) as? String
        #expect(localReadback == "1|rgb(12, 34, 56)|undefined")
        let hardened = try #require(String(data: handler.load.mainData, encoding: .utf8))
        #expect(hardened.contains("Content-Security-Policy"))
        #expect(hardened.contains("<!-- <head> -->"))
    }

    private func assertNavigationControls(
        in webView: WKWebView, host: NSView, base: URL, localFile: URL
    ) async throws {
        let mainURL = try #require(webView.url)
        let tls = try #require(URL(string: "https://127.0.0.1:\(base.port ?? 0)/denied/tls-navigation"))
        let data = try #require(URL(string: "data:text/html,<title>REPLACED</title>"))
        let attempts = [
            base.appendingPathComponent("denied/navigation"),
            tls,
            localFile,
            data,
        ]
        for target in attempts {
            _ = webView.load(URLRequest(url: target))
            try await Task.sleep(for: .milliseconds(150))
            #expect(webView.url == mainURL, "Preview navigation must refuse \(target.scheme ?? "unknown")")
            #expect(webView.title == "Contained fixture")
        }
        _ = try await webView.evaluateJavaScript("document.getElementById('attackForm').requestSubmit()")
        _ = try await webView.evaluateJavaScript("document.getElementById('attackPopup').click()")
        try await Task.sleep(for: .milliseconds(250))
        #expect(webView.url == mainURL)
        #expect(host.subviews.count == 1)
        _ = try await webView.evaluateJavaScript("document.getElementById('attackScript').click()")
        try await Task.sleep(for: .milliseconds(150))
        let scriptReadback = try await webView.evaluateJavaScript("""
        [document.title, document.getElementById('proof')?.textContent,
         typeof window.linkScriptRan].join('|')
        """) as? String
        #expect(scriptReadback == "Contained fixture|local style control|undefined")
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
        <!-- <head> --><html data-fake-head="<head>"><head><title>Contained fixture</title>
        <base href="\(address)/denied/base/">
        <link rel="stylesheet" href="local.css">
        <link rel="stylesheet" href="\(address)/denied/style.css">
        <style>@import url('\(address)/denied/import.css');
        @font-face {font-family:tripwire;src:url('\(address)/denied/font.woff2')}
        body {background:url('\(address)/denied/background.png');font-family:tripwire}</style>
        </head><body>
        <p id="proof" class="proof">local style control</p>
        <img id="local" src="local.png">
        <img src="\(address)/denied/image.png">
        <img srcset="\(address)/denied/srcset.png 1x">
        <video autoplay src="\(address)/denied/video.mp4" poster="\(address)/denied/poster.png"></video>
        <audio autoplay src="\(address)/denied/audio.mp3"></audio>
        <iframe src="\(address)/denied/frame"></iframe>
        <object data="\(address)/denied/object"></object>
        <embed src="\(address)/denied/embed">
        <script src="\(address)/denied/script.js"></script>
        <script>window.previewScriptRan=true;fetch('\(address)/denied/fetch');window.open('\(
            address
        )/denied/popup')</script>
        <form id="attackForm" action="\(address)/denied/form" method="get"><button>Submit</button></form>
        <a id="attackPopup" target="_blank" href="\(address)/denied/popup-link">Popup</a>
        <a id="attackScript" href="javascript:window.linkScriptRan=true">Script link</a>
        </body></html>
        """
    }
}

import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Preview
import Testing
import WebKit

/// Real browser tasks are forwarded unchanged to the production handler; observations never create responses.
@MainActor
final class ObservedHTMLScheme: NSObject, WKURLSchemeHandler {
    let handler: BoundedHTMLPreviewHandler
    private var tasks: [ObjectIdentifier: ObservedHTMLTask] = [:]
    var records: [ObservedHTMLTask] {
        Array(tasks.values)
    }

    init(handler: BoundedHTMLPreviewHandler) {
        self.handler = handler
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let task = ObservedHTMLTask(original: urlSchemeTask)
        tasks[ObjectIdentifier(urlSchemeTask)] = task
        handler.webView(webView, start: task)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        if let task = tasks[ObjectIdentifier(urlSchemeTask)] {
            handler.webView(webView, stop: task)
        }
    }

    func record(for url: URL?) -> ObservedHTMLTask? {
        records.first { $0.request.url == url }
    }

    func dispose() {
        handler.dispose()
        tasks.removeAll()
    }
}

@MainActor
final class ObservedHTMLTask: NSObject, @MainActor WKURLSchemeTask {
    let original: any WKURLSchemeTask
    var request: URLRequest {
        original.request
    }

    private(set) var response: URLResponse?
    private(set) var bytes = Data()
    private(set) var finished = false
    private(set) var failed = false

    init(original: any WKURLSchemeTask) {
        self.original = original
        super.init()
    }

    func didReceive(_ response: URLResponse) {
        self.response = response
        original.didReceive(response)
    }

    func didReceive(_ data: Data) {
        #expect(bytes.count + data.count <= 64 * 1024, "Only the bounded generated encoding fixtures are observed")
        bytes.append(data)
        original.didReceive(data)
    }

    func didFinish() {
        finished = true
        original.didFinish()
    }

    func didFailWithError(_ error: any Error) {
        failed = true
        original.didFailWithError(error)
    }
}

@MainActor
final class HTMLResponseEncodingFixture {
    let folder: URL
    let documentURL: URL
    let document: FileCore.FileDocument
    let tabID = UUID()
    let owner = PreviewResourceWindowState()
    let coordinator = SecuredHTMLPreviewView.Coordinator()
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    let window: NSWindow
    private var observers: [ObservedHTMLScheme] = []
    private var grants: [PreviewDirectoryGrantBacking] = []

    init(sourceBytes: Data = Data("<html><head><title>Fixture</title></head><body>Fixture</body></html>".utf8)) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        documentURL = folder.appendingPathComponent("source.html")
        do {
            try sourceBytes.write(to: documentURL)
            let snapshot = try FileStore().readSnapshot(from: documentURL)
            document = FileDocument(
                fileURL: documentURL, text: snapshot.text,
                encoding: FileEncodingMetadata(encoding: snapshot.encoding, bom: snapshot.bom)
            )
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        owner.setCurrentPreviewDocument { [weak self] in (self?.tabID, self?.document) }
    }

    func boundedPage(relativePath: String? = nil) async throws -> (WKWebView, ObservedHTMLScheme) {
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL,
            folderURL: folder
        ))
        let grant = try await PreviewDirectoryGrantBacking.acquire(
            selection: selection, currentDocumentURL: documentURL, epoch: UUID()
        )
        grants.append(grant)
        let load = try BoundedHTMLPreviewLoad(document: document, source: document.text,
                                              grant: PreviewResourceLoad(grant: grant))
        let observer = ObservedHTMLScheme(handler: BoundedHTMLPreviewHandler(load: load))
        observers.append(observer)
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(observer, forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme)
        let view = WKWebView(frame: host.bounds, configuration: configuration)
        host.addSubview(view)
        let url = relativePath.map { load.mainURL.appendingPathComponent($0) } ?? load.mainURL
        _ = try #require(view.load(URLRequest(url: url)))
        return (view, observer)
    }

    func page(title: String) async throws -> WKWebView {
        try await wait {
            self.host.subviews.compactMap { $0 as? WKWebView }.contains { $0.title == title && !$0.isLoading }
        }
        return try #require(host.subviews.compactMap { $0 as? WKWebView }.first { $0.title == title })
    }

    func wait(until ready: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if ready() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The real encoding fixture did not complete its expected browser state")
        throw BoundedHTMLPreviewError.denied
    }

    func dispose() {
        let views = host.subviews.compactMap { $0 as? WKWebView }
        for view in views {
            view.stopLoading()
        }
        coordinator.dispose(host: host)
        for observer in observers {
            observer.dispose()
        }
        observers.removeAll()
        host.subviews.forEach { $0.removeFromSuperview() }
        for grant in grants {
            grant.revoke()
        }
        grants.removeAll()
        owner.close()
        window.close()
        try? FileManager.default.removeItem(at: folder)
    }
}

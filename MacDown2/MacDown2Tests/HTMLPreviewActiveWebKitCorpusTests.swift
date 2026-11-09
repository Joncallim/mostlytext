import FileCore
import Foundation
@testable import MacDown2
import Network
import Testing
import WebKit

/// Loads saved HTML through the app's Coordinator; local assets prove rendering.
/// A permissive WebKit loopback control proves blocked requests were observable.
@MainActor
@Suite(.serialized)
struct HTMLPreviewActiveWebKitCorpusTests {
    @Test func savedPageKeepsLocalResourcesAndMakesNoRemoteConnection() async throws {
        let observer = try await LoopbackObserver.start()
        defer { observer.stop() }
        try await observer.verifyConnectionControls()
        let controlledConnectionCount = await observer.connectionCount

        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLocalControls(in: directory)

        let remoteURL = "http://127.0.0.1:\(observer.port.rawValue)/document-canary"
        let source = """
        <!doctype html><html><head>
        <meta http-equiv="refresh" content="2;url=\(remoteURL)/refresh">
        <link rel="stylesheet" href="local.css">
        </head><body>
        <p id="marker" class="proof">saved-webkit-control</p>
        <img id="local" src="local.png">
        <img id="remote" src="\(remoteURL)/image">
        <script>window.previewScriptRan = true;</script>
        </body></html>
        """
        let document = try makeDocument(source, in: directory)
        #expect(document.text == source)

        let coordinator = HTMLPreviewView.Coordinator(reloadDelay: .zero)
        let webView = coordinator.makeWebView()
        defer { coordinator.dispose(webView: webView) }
        coordinator.preview(document: document, in: webView)

        let readback = try await readUntil(
            from: webView,
            script: """
            [document.getElementById('marker')?.textContent ?? '',
             document.getElementById('local')?.naturalWidth ?? -1,
             getComputedStyle(document.getElementById('marker')).color,
             typeof window.previewScriptRan,
             document.contentType].join('|')
            """,
            satisfies: { $0 == "saved-webkit-control|1|rgb(12, 34, 56)|undefined|text/html" }
        )
        #expect(readback == "saved-webkit-control|1|rgb(12, 34, 56)|undefined|text/html")
        let attackReadback = try await readAttackMarkup(from: webView)
        #expect(attackReadback == "\(remoteURL)/image|2;url=\(remoteURL)/refresh")
        let mainURL = try #require(webView.configuration.urlSchemeHandler(
            forURLScheme: "macdown-preview"
        ) as? PreviewSchemeHandler).mainURL
        #expect(webView.url == mainURL)

        // Give the authored meta refresh and remote image time to attempt a connection.
        // The observer has already proved it can see a genuine loopback connection.
        try await Task.sleep(for: .seconds(3))
        #expect(await observer.connectionCount == controlledConnectionCount)
        #expect(webView.url == mainURL)
        let retained = try await webView.evaluateJavaScript(
            "document.getElementById('marker')?.textContent ?? ''"
        ) as? String
        #expect(retained == "saved-webkit-control")
    }

    @Test func nonUTF8HTMLRendersAndUnknownMIMEIsRefused() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeMIMEControls(in: directory)
        let document = try makeDocument(
            "<!doctype html><p id=marker>saved-main-control</p>", in: directory
        )
        let coordinator = HTMLPreviewView.Coordinator(reloadDelay: .zero)
        let webView = coordinator.makeWebView()
        defer { coordinator.dispose(webView: webView) }
        coordinator.preview(document: document, in: webView)
        let initial = try await readUntil(
            from: webView,
            script: "document.getElementById('marker')?.textContent ?? ''",
            satisfies: { $0 == "saved-main-control" }
        )
        #expect(initial == "saved-main-control")

        let handler = try #require(webView.configuration.urlSchemeHandler(
            forURLScheme: "macdown-preview"
        ) as? PreviewSchemeHandler)
        let mainURL = try #require(handler.mainURL)
        let latin1URL = mainURL.appendingPathComponent("latin1.html")
        _ = webView.load(URLRequest(url: latin1URL))
        let latin1Readback = try await readUntil(
            from: webView,
            script: """
            [document.getElementById('marker')?.textContent ?? '',
             document.contentType, document.characterSet,
             typeof window.previewScriptRan].join('|')
            """,
            satisfies: { $0 == "café|text/html|windows-1252|undefined" }
        )
        #expect(latin1Readback == "café|text/html|windows-1252|undefined")
        #expect(webView.url == latin1URL)

        // Forward WebKit's real callbacks to the production coordinator while recording the
        // MIME decision. This distinguishes a refused download from a failed page render.
        let recorder = ResponseRecorder(coordinator: coordinator)
        webView.navigationDelegate = recorder
        defer { webView.navigationDelegate = coordinator }
        let unknownURL = mainURL.appendingPathComponent("payload.unknown-preview-extension")
        _ = webView.load(URLRequest(url: unknownURL))
        let response = try await recorder.waitForResponse(at: unknownURL)
        #expect(response.mimeType == "application/octet-stream")
        // Custom-scheme navigation responses expose MIME via URLResponse;
        // WebKit does not supply an HTTP Content-Type header for this load.
        #expect(!response.canShowMIMEType)
        #expect(response.isForMainFrame)
        try await Task.sleep(for: .milliseconds(300))
        #expect(webView.url == latin1URL)
        let retained = try await webView.evaluateJavaScript(
            "document.getElementById('marker')?.textContent ?? ''"
        ) as? String
        #expect(retained == "café")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-webkit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDocument(_ source: String, in directory: URL) throws -> FileDocument {
        let file = directory.appendingPathComponent("page.html")
        try source.write(to: file, atomically: true, encoding: .utf8)
        return try FileDocument(fileURL: file).load()
    }

    private func writeLocalControls(in directory: URL) throws {
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        try png.write(to: directory.appendingPathComponent("local.png"))
        try ".proof { color: rgb(12, 34, 56); }".write(
            to: directory.appendingPathComponent("local.css"), atomically: true, encoding: .utf8
        )
    }

    private func writeMIMEControls(in directory: URL) throws {
        let latin1 = Data("<!doctype html><meta charset=windows-1252><p id=marker>caf".utf8)
            + Data([0xE9])
            + Data("</p><script>window.previewScriptRan=true</script>".utf8)
        try latin1.write(to: directory.appendingPathComponent("latin1.html"))
        try Data("unknown-mime-canary".utf8).write(
            to: directory.appendingPathComponent("payload.unknown-preview-extension")
        )
    }

    private func readAttackMarkup(from webView: WKWebView) async throws -> String? {
        try await webView.evaluateJavaScript("""
        [document.getElementById('remote')?.getAttribute('src') ?? '',
         document.querySelector('meta[http-equiv="refresh"]')?.getAttribute('content') ?? ''].join('|')
        """) as? String
    }

    private func readUntil(
        from webView: WKWebView,
        script: String,
        satisfies: (String) -> Bool
    ) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var readback = ""
        var lastError = ""
        while ContinuousClock.now < deadline {
            do {
                readback = try await webView.evaluateJavaScript(script) as? String ?? ""
                if satisfies(readback) {
                    return readback
                }
            } catch {
                lastError = "\(error)"
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let detail = "WebKit readback timed out: url=\(String(describing: webView.url)) "
            + "loading=\(webView.isLoading) readback=\(readback) error=\(lastError)"
        Issue.record("\(detail)")
        return readback
    }
}

@MainActor
private final class ResponseRecorder: NSObject, WKNavigationDelegate {
    struct Response {
        let mimeType: String?
        let contentType: String?
        let canShowMIMEType: Bool
        let isForMainFrame: Bool
    }

    private let coordinator: HTMLPreviewView.Coordinator
    private var responses: [URL: Response] = [:]

    init(coordinator: HTMLPreviewView.Coordinator) {
        self.coordinator = coordinator
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        coordinator.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if let url = navigationResponse.response.url {
            responses[url] = Response(
                mimeType: navigationResponse.response.mimeType,
                contentType: (navigationResponse.response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Content-Type"),
                canShowMIMEType: navigationResponse.canShowMIMEType,
                isForMainFrame: navigationResponse.isForMainFrame
            )
        }
        coordinator.webView(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler)
    }

    func waitForResponse(at url: URL) async throws -> Response {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while ContinuousClock.now < deadline {
            if let response = responses[url] {
                return response
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw WebKitCorpusError.timeout("No WebKit navigation response for \(url)")
    }
}

private enum WebKitCorpusError: Error {
    case timeout(String)
    case listener(String)
}

private actor LoopbackObservations {
    struct Snapshot {
        let ready: Bool
        let failure: String?
        let count: Int
    }

    private(set) var isReady = false
    private(set) var failure: String?
    private(set) var connectionCount = 0

    func markReady() {
        isReady = true
    }

    func markFailed(_ message: String) {
        failure = message
    }

    func recordConnection() {
        connectionCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(ready: isReady, failure: failure, count: connectionCount)
    }
}

@MainActor
private final class LoopbackObserver {
    let port: NWEndpoint.Port
    private let listener: NWListener
    private let observations: LoopbackObservations
    private let queue = DispatchQueue(label: "MostlyText.HTMLPreview.LoopbackObserver")

    var connectionCount: Int {
        get async { await observations.snapshot().count }
    }

    private init(listener: NWListener, observations: LoopbackObservations, port: NWEndpoint.Port) {
        self.listener = listener
        self.observations = observations
        self.port = port
    }

    static func start() async throws -> LoopbackObserver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let observations = LoopbackObservations()
        let queue = DispatchQueue(label: "MostlyText.HTMLPreview.LoopbackObserver.Start")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { await observations.markReady() }
            case let .failed(error):
                let message = String(describing: error)
                Task { await observations.markFailed(message) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            Task { await observations.recordConnection() }
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                guard data?.isEmpty == false else {
                    connection.cancel()
                    return
                }
                // Finish WebKit's control load before the zero-connection observation.
                let response = Data((
                    "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                        + "Content-Length: 2\r\nConnection: close\r\n\r\nok"
                ).utf8)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            let snapshot = await observations.snapshot()
            if let failure = snapshot.failure {
                listener.cancel()
                throw WebKitCorpusError.listener(failure)
            }
            if snapshot.ready, let port = listener.port {
                return LoopbackObserver(listener: listener, observations: observations, port: port)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        listener.cancel()
        throw WebKitCorpusError.timeout("Loopback listener did not become ready")
    }

    func verifyConnectionControls() async throws {
        let before = await connectionCount
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        connection.start(queue: queue)
        defer { connection.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await connectionCount > before {
                try await verifyWebKitConnectionControl()
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw WebKitCorpusError.timeout("Loopback connection control was not observed")
    }

    func verifyWebKitConnectionControl() async throws {
        let before = await connectionCount
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/webkit-control") else {
            throw WebKitCorpusError.listener("Invalid WebKit loopback control URL")
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let probe = WKWebView(frame: .zero, configuration: configuration)
        defer { probe.stopLoading() }
        guard probe.load(URLRequest(url: url)) != nil else {
            throw WebKitCorpusError.listener("WebKit refused the loopback control load")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var lastError = ""
        while ContinuousClock.now < deadline {
            if await connectionCount > before {
                do {
                    let text = try await probe.evaluateJavaScript("document.body?.textContent ?? ''") as? String
                    if text == "ok", probe.url == url, !probe.isLoading {
                        return
                    }
                } catch {
                    lastError = "\(error)"
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw WebKitCorpusError.timeout("WebKit loopback control did not load: \(lastError)")
    }

    func stop() {
        listener.cancel()
    }
}

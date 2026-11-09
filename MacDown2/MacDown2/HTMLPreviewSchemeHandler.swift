import FileCore
import LocalResourceAccess
import Preview
import WebKit

// MARK: - Scheme handler

/// Serves `macdown-preview://` resources for one identified preview load.
///
/// The main document and every subresource (relative image/style/font/media
/// and intra-preview navigations) arrive here. The main document is served
/// from the saved source; subresources are read beneath a descriptor pinned for
/// that saved load. Every response
/// carries the CSP header (`HTMLPreviewResponseHeaders`), which governs any
/// document the payload renders as and cannot be diverted by markup;
/// `text/html` payloads are additionally re-hardened with the meta CSP
/// injection.
///
/// Reads remain synchronous, but delivery callbacks can reenter stop or
/// request replacement. Each admitted attempt therefore owns a revocable
/// delivery token. A load also gets a unique URL authority: a delayed task
/// cannot start against a later request's resource root.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct Load {
        let request: HTMLPreviewRequest
        let documentID: String
        let recoveryEpoch: UUID
        let generation: UInt
        let authority: String
        let mainURL: URL
        let resourceRoot: DirectoryLease?
    }

    private struct DeliveryAttempt {
        let taskID: ObjectIdentifier
        let webViewID: ObjectIdentifier
        let token = UUID()
    }

    private var attempts: [ObjectIdentifier: DeliveryAttempt] = [:]

    private var load: Load?

    /// Test barrier after URL parsing but before the descriptor-based read.
    /// Production leaves this nil.
    var beforeResourceRead: (() -> Void)?

    var request: HTMLPreviewRequest? {
        load?.request
    }

    var mainURL: URL? {
        load?.mainURL
    }

    /// The URL authority is unique even when a document is saved twice with
    /// identical bytes. The immutable load binds it to one document lifetime
    /// and saved generation; an old URL can never borrow a newer root.
    func install(
        _ request: HTMLPreviewRequest,
        documentID: String,
        recoveryEpoch: UUID,
        generation: UInt
    ) -> URL? {
        let authority = UUID().uuidString.lowercased()
        guard let mainURL = URL(string: "\(HTMLPreviewNavigationPolicy.previewURLScheme)://\(authority)/")
        else { return nil }
        attempts.removeAll()
        load?.resourceRoot?.close()
        // Pin this saved revision's directory before a later scheme task can
        // observe a replaced pathname. Main HTML still renders if its root is
        // unavailable; subresources then fail closed.
        let resourceRoot = request.baseURL.flatMap { try? DirectoryLease(opening: $0) }
        load = Load(
            request: request,
            documentID: documentID,
            recoveryEpoch: recoveryEpoch,
            generation: generation,
            authority: authority,
            mainURL: mainURL,
            resourceRoot: resourceRoot
        )
        return mainURL
    }

    func retire() {
        attempts.removeAll()
        load?.resourceRoot?.close()
        load = nil
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID] == nil else { return }
        let attempt = DeliveryAttempt(taskID: taskID, webViewID: ObjectIdentifier(webView))
        attempts[taskID] = attempt
        // Validate the authority too: the scheme handler is the containment
        // boundary, so host/userinfo/port abuse must fail closed even though
        // the current path mapping ignores them.
        guard let url = task.request.url,
              url.scheme?.lowercased() == HTMLPreviewNavigationPolicy.previewURLScheme,
              let load,
              url.host == load.authority,
              url.user == nil,
              url.password == nil,
              url.port == nil
        else {
            fail(task, attempt: attempt)
            return
        }
        guard isLive(attempt) else { return }
        if url.path.isEmpty || url.path == "/" {
            serveMainDocument(request: load.request, url: url, task: task, attempt: attempt)
            return
        }
        serveSubresource(request: load.request, root: load.resourceRoot,
                         url: url, task: task, attempt: attempt)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID]?.webViewID == ObjectIdentifier(webView) else { return }
        attempts.removeValue(forKey: taskID)
    }

    private func isLive(_ attempt: DeliveryAttempt) -> Bool {
        attempts[attempt.taskID]?.token == attempt.token
    }

    private func consume(_ attempt: DeliveryAttempt) -> Bool {
        guard isLive(attempt) else { return false }
        attempts.removeValue(forKey: attempt.taskID)
        return true
    }

    private func fail(_ task: WKURLSchemeTask, attempt: DeliveryAttempt) {
        guard consume(attempt) else { return }
        task.didFailWithError(PreviewSchemeError.denied)
    }

    /// Serves the main document: the saved source with the belt-and-braces
    /// meta-CSP injection plus the authoritative CSP response header.
    private func serveMainDocument(
        request: HTMLPreviewRequest,
        url: URL,
        task: WKURLSchemeTask,
        attempt: DeliveryAttempt
    ) {
        let hardened = PreviewSecurity.hardenedHTMLDocument(from: request.source)
        serve(
            Data(hardened.utf8),
            headers: HTMLPreviewResponseHeaders.headers(
                for: request.policy,
                contentType: HTMLPreviewContentType.mainDocument
            ),
            url: url,
            task: task,
            attempt: attempt
        )
    }

    private func serveSubresource(
        request: HTMLPreviewRequest,
        root: DirectoryLease?,
        url: URL,
        task: WKURLSchemeTask,
        attempt: DeliveryAttempt
    ) {
        guard let root else {
            // Untitled documents have no approved resource root.
            fail(task, attempt: attempt)
            return
        }
        // Parse the encoded path exactly once. The reader's canonical hint
        // chooses an in-root target; only its openat flags authorize bytes.
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              let reference = try? ResourceReference.parse(path)
        else {
            fail(task, attempt: attempt)
            return
        }
        beforeResourceRead?()
        // Preserve this active handler's existing size behavior. A separate
        // issue #13 slice must set and measure an explicit resource budget.
        guard let snapshot = try? ContainedResourceReader.read(reference, in: root, maxBytes: Int.max)
        else { fail(task, attempt: attempt); return }
        let data = snapshot.bytes

        // Re-harden HTML payloads with the meta CSP; everything else — images,
        // fonts, media — is served raw. Either way the response carries the
        // CSP header, so payloads the meta injection cannot harden (non-UTF-8
        // HTML, SVG, XML) are still governed by the authoritative header.
        let fileExtension = (snapshot.name as NSString).pathExtension
        let mimeType = HTMLPreviewContentType.forFileExtension(fileExtension)
        var contentType = mimeType
        let responseData: Data
        if HTMLPreviewContentType.isHTML(fileExtension) {
            // The failable initializer is deliberate: a payload that is not
            // valid UTF-8 cannot be meta-hardened, so it is served raw and
            // the browser applies its own encoding detection — the CSP
            // header still applies.
            if let decoded = String(bytes: data, encoding: .utf8) {
                responseData = Data(PreviewSecurity.hardenedHTMLDocument(from: decoded).utf8)
                contentType = HTMLPreviewContentType.mainDocument
            } else {
                responseData = data
            }
        } else {
            responseData = data
        }
        serve(
            responseData,
            headers: HTMLPreviewResponseHeaders.headers(for: request.policy, contentType: contentType),
            url: url,
            task: task,
            attempt: attempt
        )
    }

    /// Finishes `task` with `data` and the hardening response headers.
    private func serve(
        _ data: Data,
        headers: [String: String],
        url: URL,
        task: WKURLSchemeTask,
        attempt: DeliveryAttempt
    ) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fail(task, attempt: attempt)
            return
        }
        guard isLive(attempt) else { return }
        task.didReceive(response)
        guard isLive(attempt) else { return }
        task.didReceive(data)
        // Terminalize before calling out: a callback may admit another attempt.
        guard consume(attempt) else { return }
        task.didFinish()
    }
}

private enum PreviewSchemeError: Error {
    case denied
}

// MARK: - Security scope

/// Balances `startAccessingSecurityScopedResource` for the preview's resource
/// root. Non-sandboxed builds report `false` from `startAccessing…` and the
/// matching `stopAccessing…` is a documented no-op, so the wrapper is safe in
/// both configurations; sandboxed builds hold the scope for the lifetime of
/// the previewed revision.
@MainActor
final class PreviewSecurityScope {
    private let url: URL
    private let accessed: Bool

    init?(url: URL) {
        self.url = url
        accessed = url.startAccessingSecurityScopedResource()
    }

    func stop() {
        if accessed {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

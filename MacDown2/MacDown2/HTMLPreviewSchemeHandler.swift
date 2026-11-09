import FileCore
import LocalResourceAccess
import Preview
import WebKit

// MARK: - Scheme handler

/// Serves `macdown-preview://` resources for one identified preview load.
///
/// The main document and every subresource (relative image/style/font/media
/// and intra-preview navigations) arrive here. The main document is served
/// from the saved source; subresources are read on bounded workers beneath a
/// descriptor pinned for that saved load. Every response
/// carries the CSP header (`HTMLPreviewResponseHeaders`), which governs any
/// document the payload renders as and cannot be diverted by markup;
/// `text/html` payloads are additionally re-hardened with the meta CSP
/// injection.
///
/// Delivery callbacks can reenter stop or request replacement. Each admitted
/// attempt therefore owns a revocable delivery token. A load also gets a
/// unique URL authority: a delayed task cannot borrow a later resource root.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct Load {
        let id = UUID()
        let request: HTMLPreviewRequest
        let documentID: String
        let recoveryEpoch: UUID
        let generation: UInt
        let authority: String
        let mainURL: URL
        let resourceLoad: PreviewResourceLoad?
        let copyBudget = PreviewHTMLCopyBudget()
    }

    private struct DeliveryIdentity {
        let taskID: ObjectIdentifier
        let webViewID: ObjectIdentifier
        let token = UUID()
        let loadID: UUID?
    }

    private struct DeliveryAttempt {
        let identity: DeliveryIdentity
        let task: any WKURLSchemeTask
        var worker: Task<Void, Never>?
    }

    private let admission: PreviewResourceAdmission
    private var attempts: [ObjectIdentifier: DeliveryAttempt] = [:]

    private var load: Load?

    /// Test barrier after URL parsing but before the descriptor-based read.
    /// Production leaves this nil.
    var beforeResourceRead: (() -> Void)?

    init(admission: PreviewResourceAdmission = .shared) {
        self.admission = admission
        super.init()
    }

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
        documentURL: URL?,
        documentID: String,
        recoveryEpoch: UUID,
        generation: UInt
    ) -> URL? {
        let authority = UUID().uuidString.lowercased()
        guard let mainURL = URL(string: "\(HTMLPreviewNavigationPolicy.previewURLScheme)://\(authority)/")
        else { return nil }
        retire()
        // Pin this saved revision's directory before a later scheme task can
        // observe a replaced pathname. Main HTML still renders if its root is
        // unavailable; subresources then fail closed. The saved document URL
        // must agree with the request's parent: a caller cannot retarget it.
        let resourceLoad: PreviewResourceLoad? = if let documentURL,
                                                    request.baseURL == documentURL.deletingLastPathComponent(),
                                                    let backing = try? PreviewDirectoryGrantBacking.acquireAutomatic(
                                                        documentURL: documentURL, epoch: recoveryEpoch
                                                    ) {
            PreviewResourceLoad(grant: backing)
        } else {
            nil
        }
        load = Load(
            request: request,
            documentID: documentID,
            recoveryEpoch: recoveryEpoch,
            generation: generation,
            authority: authority,
            mainURL: mainURL,
            resourceLoad: resourceLoad
        )
        return mainURL
    }

    func retire() {
        let workers = attempts.values.compactMap(\.worker)
        attempts.removeAll()
        for worker in workers {
            worker.cancel()
        }
        if let context = load?.resourceLoad {
            // Revoke synchronously before actor retirement can run. An admitted
            // worker retains its descriptor/scope through the backing's Use.
            context.revoke()
            context.grant.revoke()
            let admission = admission
            Task { await admission.retire(context) }
        }
        load = nil
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID] == nil else { return }
        let identity = DeliveryIdentity(
            taskID: taskID, webViewID: ObjectIdentifier(webView), loadID: load?.id
        )
        attempts[taskID] = DeliveryAttempt(identity: identity, task: task)
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
            fail(identity)
            return
        }
        guard isLive(identity) else { return }
        if url.path.isEmpty || url.path == "/" {
            serveMainDocument(request: load.request, url: url, identity: identity)
            return
        }
        serveSubresource(load: load, url: url, identity: identity)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID]?.identity.webViewID == ObjectIdentifier(webView) else { return }
        attempts.removeValue(forKey: taskID)?.worker?.cancel()
    }

    private func isLive(_ identity: DeliveryIdentity) -> Bool {
        attempts[identity.taskID]?.identity.token == identity.token && load?.id == identity.loadID
    }

    private func consume(_ identity: DeliveryIdentity) -> DeliveryAttempt? {
        guard isLive(identity) else { return nil }
        return attempts.removeValue(forKey: identity.taskID)
    }

    private func fail(_ identity: DeliveryIdentity) {
        guard let attempt = consume(identity) else { return }
        attempt.task.didFailWithError(PreviewSchemeError.denied)
    }

    /// Serves the main document: the saved source with the belt-and-braces
    /// meta-CSP injection plus the authoritative CSP response header.
    private func serveMainDocument(
        request: HTMLPreviewRequest,
        url: URL,
        identity: DeliveryIdentity
    ) {
        let hardened = PreviewSecurity.hardenedHTMLDocument(from: request.source)
        serve(
            Data(hardened.utf8),
            headers: HTMLPreviewResponseHeaders.headers(
                for: request.policy,
                contentType: HTMLPreviewContentType.mainDocument
            ),
            url: url,
            identity: identity
        )
    }

    private func serveSubresource(
        load: Load,
        url: URL,
        identity: DeliveryIdentity
    ) {
        guard let context = load.resourceLoad else {
            // Untitled documents have no approved resource root.
            fail(identity)
            return
        }
        // Parse the encoded path exactly once. The reader's canonical hint
        // chooses an in-root target; only its openat flags authorize bytes.
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              let reference = try? ResourceReference.parse(path)
        else {
            fail(identity)
            return
        }
        beforeResourceRead?()
        guard isLive(identity) else { return }
        let admission = admission
        let policy = load.request.policy
        let copyBudget = load.copyBudget
        let worker = Task { [weak self] in
            do {
                let payload = try await admission.read(reference, in: context)
                self?.deliver(payload, policy: policy, copyBudget: copyBudget,
                              url: url, identity: identity)
            } catch {
                self?.fail(identity)
            }
        }
        attempts[identity.taskID]?.worker = worker
    }

    private func deliver(
        _ payload: PreviewResourcePayload,
        policy: HTMLPreviewPolicy,
        copyBudget: PreviewHTMLCopyBudget,
        url: URL,
        identity: DeliveryIdentity
    ) {
        guard isLive(identity) else { return }
        let snapshot = payload.snapshot
        let data = snapshot.bytes

        // Re-harden HTML payloads with the meta CSP; everything else — images,
        // fonts, media — is served raw. Either way the response carries the
        // CSP header, so payloads the meta injection cannot harden (non-UTF-8
        // HTML, SVG, XML) are still governed by the authoritative header.
        let fileExtension = (snapshot.name as NSString).pathExtension
        let mimeType = HTMLPreviewContentType.forFileExtension(fileExtension)
        var contentType = mimeType
        let responseData: Data
        var copyReservation: PreviewHTMLCopyBudget.Reservation?
        if HTMLPreviewContentType.isHTML(fileExtension) {
            // Charge extra string/character/encoded copies before decoding.
            // Invalid UTF-8 still uses the CSP header on the raw bytes.
            guard let reservation = try? copyBudget.reserve(
                PreviewHTMLCopyBudget.hardeningCharge(for: data.count)
            ) else { fail(identity); return }
            copyReservation = reservation
            // The failable initializer is deliberate: a payload that is not
            // valid UTF-8 cannot be meta-hardened, so it is served raw and
            // the browser applies its own encoding detection — the CSP
            // header still applies.
            if let decoded = String(bytes: data, encoding: .utf8) {
                responseData = Data(PreviewSecurity.hardenedHTMLDocument(from: decoded).utf8)
                guard responseData.count <= BoundedHTMLPreviewLoad.encodedLimit else {
                    fail(identity)
                    return
                }
                contentType = HTMLPreviewContentType.mainDocument
            } else {
                responseData = data
            }
        } else {
            responseData = data
        }
        withExtendedLifetime((payload, copyReservation)) {
            serve(
                responseData,
                headers: HTMLPreviewResponseHeaders.headers(for: policy, contentType: contentType),
                url: url,
                identity: identity
            )
        }
    }

    /// Finishes `task` with `data` and the hardening response headers.
    private func serve(
        _ data: Data,
        headers: [String: String],
        url: URL,
        identity: DeliveryIdentity
    ) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fail(identity)
            return
        }
        guard isLive(identity), let attempt = attempts[identity.taskID] else { return }
        attempt.task.didReceive(response)
        guard isLive(identity) else { return }
        attempt.task.didReceive(data)
        // Terminalize before calling out: a callback may admit another attempt.
        guard let completed = consume(identity) else { return }
        completed.task.didFinish()
    }
}

private enum PreviewSchemeError: Error {
    case denied
}

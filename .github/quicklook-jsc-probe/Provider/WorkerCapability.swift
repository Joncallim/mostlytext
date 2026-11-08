import Darwin
import Foundation
import OSLog
import QuickLookUI

/// Private Finder fixture: two fixed requests share one service connection,
/// but each service request owns a separate child and monotonic deadline.
enum WorkerCapability {
    private static let logger = Logger(subsystem: "app.mostlytext.qljscprobe", category: "provider")

    static func preparePair(requestID: Int, source: Data) -> QLPreviewReply {
        // Prepare the source fallback before the renderer is contacted. No
        // worker response can replace or mutate the captured source bytes.
        let fallback = makeReply(source: source, isolated: false)
        guard requestID > 0, requestID <= Int.max / 2 else { return fallback }
        let heldID = requestID * 2
        let normalID = heldID + 1
        let handshake = WorkerResponse()
        let held = WorkerResponse()
        let normal = WorkerResponse()
        let connection = NSXPCConnection(serviceName: "app.mostlytext.QLReplyProbe.XPCService")
        connection.remoteObjectInterface = NSXPCInterface(with: QLXPCCapabilityService.self)
        connection.interruptionHandler = { handshake.fail(); held.fail(); normal.fail() }
        connection.invalidationHandler = { handshake.fail(); held.fail(); normal.fail() }
        connection.resume()
        defer { connection.invalidate() }
        guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
            logger.error("QL_WORKER_BOUNDARY transport-error domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
            handshake.fail()
            held.fail()
            normal.fail()
        }) as? QLXPCCapabilityService else { return fallback }
        let pingStarted = ProcessInfo.processInfo.systemUptime
        remote.ping(NSNumber(value: requestID)) { marker, id, service, sandbox in
            handshake.finish(WorkerReply(marker: marker as String, id: id.intValue,
                                         service: service.int32Value, worker: 0,
                                         sandbox: sandbox.intValue))
        }
        guard let ping = handshake.wait(until: pingStarted + 2.0),
              ping.marker == "MOSTLYTEXT_QL_XPC_PING_OK", ping.id == requestID,
              ping.service > 0, ping.service != getpid(), ping.sandbox == 1 else { return fallback }
        let serviceStarted = ProcessInfo.processInfo.systemUptime
        logger.notice("QL_WORKER_BOUNDARY pair-begin id=\(requestID) provider=\(getpid()) at=\(serviceStarted)")
        remote.render(NSNumber(value: heldID), mode: "held") { marker, id, service, worker, sandbox in
            held.finish(WorkerReply(marker: marker as String, id: id.intValue,
                                    service: service.int32Value, worker: worker.int32Value,
                                    sandbox: sandbox.intValue))
        }
        // The normal worker must still be alive when the held worker expires.
        // Its own deadline begins only when this second request is sent.
        Thread.sleep(forTimeInterval: 1.0)
        let normalStarted = ProcessInfo.processInfo.systemUptime
        remote.render(NSNumber(value: normalID), mode: "normal") { marker, id, service, worker, sandbox in
            normal.finish(WorkerReply(marker: marker as String, id: id.intValue,
                                      service: service.int32Value, worker: worker.int32Value,
                                      sandbox: sandbox.intValue))
        }
        let heldReply = held.wait(until: serviceStarted + 2.0)
        let normalReply = normal.wait(until: normalStarted + 2.0)
        let finished = ProcessInfo.processInfo.systemUptime
        let isolated = heldReply?.marker == "timedOut" && heldReply?.id == heldID
            && normalReply?.marker == "completed" && normalReply?.id == normalID
            && heldReply?.sandbox == 1 && normalReply?.sandbox == 1
            && (heldReply?.worker ?? 0) > 0 && (normalReply?.worker ?? 0) > 0
            && heldReply?.worker != normalReply?.worker
            && heldReply?.service == normalReply?.service
            && heldReply?.service == ping.service
        logger.notice("QL_WORKER_BOUNDARY pair-finished id=\(requestID) provider=\(getpid()) held=\(heldReply?.marker ?? "missing", privacy: .public) heldWorker=\(heldReply?.worker ?? 0) normal=\(normalReply?.marker ?? "missing", privacy: .public) normalWorker=\(normalReply?.worker ?? 0) service=\(normalReply?.service ?? 0) isolated=\(isolated) at=\(finished)")
        return isolated ? makeReply(source: source, isolated: true) : fallback
    }

    private static func makeReply(source: Data, isolated: Bool) -> QLPreviewReply {
        let sourceText = String(decoding: source, as: UTF8.self)
        let escaped = sourceText.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        let marker = isolated ? "MOSTLYTEXT_QL_WORKER_ISOLATION_OK" : "MOSTLYTEXT_QL_WORKER_SOURCE_FALLBACK"
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'">
        <h1>\(marker)</h1><pre>\(escaped)</pre>
        """.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in html }
        reply.title = "MostlyText bounded worker fixture"
        reply.stringEncoding = .utf8
        return reply
    }

    private struct WorkerReply {
        let marker: String
        let id: Int
        let service: Int32
        let worker: Int32
        let sandbox: Int
    }

    private final class WorkerResponse: @unchecked Sendable {
        private let lock = NSLock()
        private let signal = DispatchSemaphore(value: 0)
        private var value: WorkerReply?
        private var finished = false

        func finish(_ reply: WorkerReply) {
            lock.lock()
            let first = !finished
            if first { value = reply; finished = true }
            lock.unlock()
            if first { signal.signal() }
        }

        func fail() {
            lock.lock()
            let first = !finished
            if first { finished = true }
            lock.unlock()
            if first { signal.signal() }
        }

        func wait(until deadline: Double) -> WorkerReply? {
            let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            guard signal.wait(timeout: .now() + remaining) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}

import Darwin
import Foundation
import OSLog
import QuickLookUI

@objc(QLXPCCapabilityService) protocol QLXPCCapabilityService {
    func ping(_ requestID: NSNumber, withReply reply: @escaping (NSString, NSNumber, NSNumber, NSNumber) -> Void)
}

/// One fixed bundled-service reachability control; never accepts document data.
enum XPCCapability {
    private static let logger = Logger(subsystem: "app.mostlytext.qljscprobe", category: "provider")

    static func prepare(requestID: Int) throws -> QLPreviewReply {
        guard requestID > 0 else { throw Failure.refused }
        let connection = NSXPCConnection(serviceName: "app.mostlytext.QLReplyProbe.XPCService")
        connection.remoteObjectInterface = NSXPCInterface(with: QLXPCCapabilityService.self)
        let response = Response()
        connection.interruptionHandler = { response.finish(.failure(Failure.interrupted)) }
        connection.invalidationHandler = { response.finish(.failure(Failure.invalidated)) }
        connection.resume()
        defer { connection.invalidate() }
        guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
            let value = error as NSError
            logger
                .error(
                    "QL_XPC_PROBE error id=\(requestID) domain=\(value.domain, privacy: .public) code=\(value.code) description=\(value.description, privacy: .public)"
                )
            response.finish(.failure(error))
        }) as? QLXPCCapabilityService else { throw Failure.refused }
        logger
            .notice(
                "QL_XPC_PROBE begin id=\(requestID) provider=\(getpid()) start=\(ProcessInfo.processInfo.systemUptime)"
            )
        remote.ping(NSNumber(value: requestID)) { marker, observedID, pid, sandbox in
            response.finish(.success(Reply(
                marker: marker as String, requestID: observedID.intValue,
                servicePID: pid.intValue, sandbox: sandbox.intValue
            )))
        }
        guard let result = response.wait(seconds: 3) else {
            logger.error("QL_XPC_PROBE timeout id=\(requestID)")
            throw Failure.timeout
        }
        let observed = try result.get()
        guard observed.marker == "MOSTLYTEXT_QL_XPC_PING_OK", observed.requestID == requestID,
              observed.servicePID > 0, observed.servicePID != getpid(), observed.sandbox == 1
        else { throw Failure.refused }
        logger.notice("QL_XPC_PROBE admitted id=\(requestID) provider=\(getpid()) service=\(observed.servicePID)")
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'">
        <h1>MOSTLYTEXT_QL_XPC_PING_OK</h1>
        <p>Fixed hosted service reachability control only.</p>
        """.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in html }
        reply.title = "MostlyText XPC reachability control"
        reply.stringEncoding = .utf8
        return reply
    }

    private struct Reply {
        let marker: String
        let requestID: Int
        let servicePID: Int
        let sandbox: Int
    }

    private final class Response: @unchecked Sendable {
        private let lock = NSLock()
        private let signal = DispatchSemaphore(value: 0)
        private var value: Result<Reply, Error>?

        func finish(_ result: Result<Reply, Error>) {
            lock.lock()
            let first = value == nil
            if first {
                value = result
            }
            lock.unlock()
            if first {
                signal.signal()
            }
        }

        func wait(seconds: Int) -> Result<Reply, Error>? {
            guard signal.wait(timeout: .now() + .seconds(seconds)) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private enum Failure: Error { case refused, interrupted, invalidated, timeout }
}

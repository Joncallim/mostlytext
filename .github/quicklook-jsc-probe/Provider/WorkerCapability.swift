import CryptoKit
import Darwin
import Foundation
import OSLog
import QuickLookUI

/// Sandbox inheritance and physical process retirement only, never a production renderer.
enum WorkerCapability {
    private static let logger = Logger(subsystem: "app.mostlytext.qljscprobe", category: "provider")

    static func prepare(requestID: Int) throws -> QLPreviewReply {
        guard let provider = Bundle(for: StaticPreview.self).executableURL else { throw Failure.refused }
        let worker = provider.deletingLastPathComponent().appendingPathComponent("QLReplyProbeWorker")
        guard worker.resolvingSymlinksInPath() == worker,
              let regular = try worker.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, regular
        else { throw Failure.refused }
        let workerHash = try SHA256.hash(data: Data(contentsOf: worker)).map { String(format: "%02x", $0) }.joined()
        let start = ProcessInfo.processInfo.systemUptime
        let parent = getpid()
        logger.notice("QL_WORKER_PROBE begin id=\(requestID) parent=\(parent) start=\(start)")
        logger.notice("QL_WORKER_PROBE executable id=\(requestID) sha256=\(workerHash, privacy: .public)")
        let normal = try run(worker, mode: "normal", requestID: requestID, parent: parent)
        let held = try run(worker, mode: "held", requestID: requestID, parent: parent)
        guard normal["pid"] as? Int != held["pid"] as? Int else { throw Failure.refused }
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'">
        <h1>MOSTLYTEXT_QL_WORKER_NORMAL_OK</h1><h2>MOSTLYTEXT_QL_WORKER_HARD_LIMIT_OK</h2>
        <p>Fixed inherited worker controls only; no untrusted renderer admission.</p>
        """.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            logger.notice("QL_WORKER_PROBE factory id=\(requestID) bytes=\(html.count)")
            return html
        }
        reply.title = "MostlyText inherited worker control"
        reply.stringEncoding = .utf8
        return reply
    }

    private static func run(_ worker: URL, mode: String, requestID: Int, parent: pid_t) throws -> [String: Any] {
        let process = Process()
        process.executableURL = worker
        process.arguments = [mode, String(requestID), String(parent)]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let start = ProcessInfo.processInfo.systemUptime
        do { try process.run() } catch {
            recordSpawnError(error as NSError, worker: worker, process: process, mode: mode, requestID: requestID)
            logger.error("QL_WORKER_PROBE spawn-refused id=\(requestID) code=\((error as NSError).code)")
            throw error
        }
        let child = process.processIdentifier
        guard child > 0 else { throw Failure.refused }
        process.waitUntilExit()
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        let data = try output.fileHandleForReading.read(upToCount: 1025) ?? Data()
        let extra = try output.fileHandleForReading.read(upToCount: 1) ?? Data()
        let stderr = try errors.fileHandleForReading.read(upToCount: 4097) ?? Data()
        logger.notice("QL_WORKER_PROBE exited id=\(requestID) pid=\(child) status=\(process.terminationStatus)")
        guard data.count < 1024, extra.isEmpty, stderr.isEmpty,
              var record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              record["request_id"] as? Int == requestID, record["mode"] as? String == mode,
              record["pid"] as? Int32 == child, record["ppid"] as? Int32 == parent,
              record["sandbox"] as? Bool == true, record["inherit"] as? Bool == true,
              kill(child, 0) == -1, errno == ESRCH, (0 ..< 3000).contains(elapsed)
        else { throw Failure.refused }
        record["reason"] = process.terminationReason == .exit ? "exit" : "signal"
        record["status"] = process.terminationStatus
        record["gone"] = true
        record["elapsed_ms"] = elapsed
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard encoded.count <= 384, let json = String(data: encoded, encoding: .utf8) else { throw Failure.refused }
        logger.notice("QL_WORKER_PROBE child=\(json, privacy: .public)")
        guard (mode == "normal" && process.terminationReason == .exit && process.terminationStatus == 0)
            || (mode == "held" && process.terminationReason == .uncaughtSignal
                && process.terminationStatus == SIGKILL && elapsed >= 450)
        else { throw Failure.refused }
        return record
    }

    private static func recordSpawnError(
        _ error: NSError, worker: URL, process: Process, mode: String, requestID: Int
    ) {
        func bounded(_ value: String, limit: Int) -> String {
            String(bytes: value.utf8.prefix(limit), encoding: .utf8) ?? "<incomplete UTF8 prefix>"
        }
        func errorFields(_ value: NSError) -> [String: Any] {
            [
                "domain": bounded(value.domain, limit: 128), "code": value.code,
                "description": bounded(value.localizedDescription, limit: 512),
                "domain_utf8_bytes": value.domain.utf8.count,
                "description_utf8_bytes": value.localizedDescription.utf8.count,
            ]
        }
        var underlying: [[String: Any]] = []
        var current = error
        for _ in 0 ..< 2 {
            guard let next = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            underlying.append(errorFields(next))
            current = next
        }
        let readable = access(worker.path, R_OK)
        let readError = readable == 0 ? 0 : errno
        let executable = access(worker.path, X_OK)
        let executeError = executable == 0 ? 0 : errno
        let attributes = try? FileManager.default.attributesOfItem(atPath: worker.path)
        let record: [String: Any] = [
            "kind": "mostlytext-qlworker-spawn-error", "request_id": requestID,
            "provider_pid": getpid(), "mode": mode, "error": errorFields(error), "underlying": underlying,
            "worker_path": bounded(worker.path, limit: 768),
            "unix_permissions": attributes?[.posixPermissions] ?? NSNull(),
            "read_access": readable, "read_errno": readError,
            "execute_access": executable, "execute_errno": executeError,
            "current_directory": bounded(FileManager.default.currentDirectoryPath, limit: 768),
            "process_directory": process.currentDirectoryURL.map { bounded($0.path, limit: 768) } as Any? ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              data.count <= 4096 else {
            logger.error("QL_WORKER_PROBE spawn-error-encoding-refused id=\(requestID)")
            return
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let total = (data.count + 383) / 384
        for part in 0 ..< total {
            let payload = data.subdata(in: part * 384 ..< min((part + 1) * 384, data.count)).base64EncodedString()
            let message = "QL_WORKER_PROBE spawn-error id=\(requestID) part=\(part) total=\(total) " +
                "sha256=\(hash) data=\(payload)"
            logger.error("\(message, privacy: .public)")
        }
    }

    private enum Failure: Error { case refused }
}

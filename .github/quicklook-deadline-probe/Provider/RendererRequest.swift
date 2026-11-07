import CryptoKit
import D2Rendering
import DiagramsD2
import Foundation
import OSLog
import QuickLookUI

/// No product orchestration is implemented here: this only brackets the real API.
enum RendererRequest {
    private static let renderer = D2WebRenderer(poolSize: 1)
    private static let occupancy = RendererOccupancy()
    private static let logger = Logger(subsystem: "app.mostlytext.qldeadlineprobe", category: "provider")

    static func source(large: Bool) -> String {
        if !large {
            return "MT_D2_SMALL_CONTROL -> b\n"
        }
        return (0 ..< 1536).map { "n\($0) -> n\($0 + 1)\nn\($0) -> n\($0 + 2)\n" }.joined()
    }

    private struct Work: Sendable {
        let source: String
        let id: Int
        let deadline: ContinuousClock.Instant
        let fallback: PreparedReply
        let gate: DeadlineGate
        let lease: RendererOccupancy.Lease
    }

    static func prepare(source: String, requestID: Int) async -> PreparedReply {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        event("callback", id: requestID)
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let fallback = payload(.fallback, marker: "MOSTLYTEXT_QL_D2_FALLBACK", body: "<pre>\(escaped)</pre>")
        guard let lease = occupancy.acquire() else {
            event("selected-busy", id: requestID)
            return payload(.busy, marker: "MOSTLYTEXT_QL_D2_BUSY", body: "Renderer occupancy remains charged.")
        }
        let gate = DeadlineGate()
        let work = Work(source: source, id: requestID, deadline: deadline,
                        fallback: fallback, gate: gate, lease: lease)
        Task.detached { await derive(work) }
        Task.detached {
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            gate.select(fallback) { event("selected-fallback", id: requestID) }
        }
        return await gate.value()
    }

    static func reply(_ value: PreparedReply, requestID: Int) -> QLPreviewReply {
        let digest = SHA256.hash(data: value.html).map { String(format: "%02x", $0) }.joined()
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            event("factory-" + value.kind.rawValue, id: requestID)
            logger
                .notice(
                    "QL_DEADLINE_BYTES id=\(requestID) bytes=\(value.html.count) sha256=\(digest, privacy: .public)"
                )
            return value.html
        }
        reply.title = "MostlyText real D2 deadline probe"
        reply.stringEncoding = .utf8
        event("reply-" + value.kind.rawValue, id: requestID)
        return reply
    }

    static func event(_ phase: String, id: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        logger.notice("QL_DEADLINE_PROBE \(phase, privacy: .public) id=\(id) uptime=\(now, privacy: .public)")
    }

    private static func derive(_ work: Work) async {
        event("worker-start", id: work.id)
        do {
            let result = try await renderer.render(
                D2Fence(source: work.source, sourceRange: 0 ..< work.source.utf16.count), context: .neutralLight
            )
            event("worker-terminal", id: work.id)
            work.lease.releaseAfterActualWorkerReturn()
            let valid = result.svg.contains("<svg") && !result.svg.isEmpty
                && (work.source != source(large: false) || result.svg.contains("MT_D2_SMALL_CONTROL"))
            finish(work, candidate: valid
                ? payload(.rich, marker: "MOSTLYTEXT_QL_D2_RICH", body: result.svg)
                : payload(.failed, marker: "MOSTLYTEXT_QL_D2_ERROR", body: "Actual SVG control missing."))
        } catch {
            let detail = String(String(describing: error).prefix(2048))
            logger.error("QL_DEADLINE_RENDER_ERROR id=\(work.id) detail=\(detail, privacy: .public)")
            event("worker-terminal", id: work.id)
            work.lease.releaseAfterActualWorkerReturn()
            finish(work, candidate: payload(.failed, marker: "MOSTLYTEXT_QL_D2_ERROR", body: "Actual renderer failed."))
        }
    }

    private static func finish(_ work: Work, candidate: PreparedReply) {
        let value = ContinuousClock.now >= work.deadline ? work.fallback : candidate
        let selected = work.gate.select(value) { event("selected-" + value.kind.rawValue, id: work.id) }
        if !selected {
            event(candidate.kind == .rich ? "late-rich" : "late-error", id: work.id)
        }
    }

    private static func payload(_ kind: PreparedReply.Kind, marker: String, body: String) -> PreparedReply {
        let policy = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'"
        return PreparedReply(kind: kind, html: Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        <h1>\(marker)</h1>\(body)
        """.utf8))
    }
}

import Darwin
import Foundation
import OSLog
import QuickLookUI
import Security
import Synchronization

/// Standalone hosted fixture, not a shipping renderer or root-project target.
final class StaticPreview: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(subsystem: "app.mostlytext.qldeadlineprobe", category: "provider")
    private static let nextID = Mutex(0)

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let file = request.fileURL
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              FileManager.default.homeDirectoryForCurrentUser.path.hasPrefix("/Users/runner/"),
              file.path.hasPrefix("/Users/runner/work/_temp/mostlytext-qldeadline/"),
              ["mostlytext-ql-reply-static.md", "mostlytext-ql-d2-small.md", "mostlytext-ql-d2-large.md"]
              .contains(file.lastPathComponent)
        else { throw ProbeError.refused }
        guard let task = SecTaskCreateFromSelf(nil) else { throw ProbeError.refused }
        let required = ["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-only"]
        let forbidden = [
            "com.apple.security.get-task-allow",
            "com.apple.security.network.client",
            "com.apple.security.network.server",
            "com.apple.security.application-groups",
            "com.apple.security.temporary-exception.files.absolute-path.read-only",
            "com.apple.security.temporary-exception.files.absolute-path.read-write",
            "com.apple.security.temporary-exception.mach-lookup.global-name",
            "com.apple.security.temporary-exception.mach-lookup.local-name",
            "com.apple.security.temporary-exception.sbpl",
            "com.apple.security.inherit",
        ]
        guard required.allSatisfy({ SecTaskCopyValueForEntitlement(task, $0 as CFString, nil) as? Bool == true }),
              forbidden.allSatisfy({ SecTaskCopyValueForEntitlement(task, $0 as CFString, nil) == nil })
        else {
            Self.logger.error("QL_REPLY_PROBE self-entitlement-policy-refused")
            throw ProbeError.refused
        }
        Self.logger.notice("QL_REPLY_PROBE self-entitlement-policy-admitted")
        let requestID = Self.nextID.withLock { count in count += 1; return count }
        Self.logger.notice("QL_REPLY_PROBE callback id=\(requestID) main=\(Thread.isMainThread)")
        try readSelectedAndCheckSibling(file)
        if file.lastPathComponent != "mostlytext-ql-reply-static.md" {
            let source = RendererRequest.source(large: file.lastPathComponent == "mostlytext-ql-d2-large.md")
            let prepared = await RendererRequest.prepare(source: source, requestID: requestID)
            return RendererRequest.reply(prepared, requestID: requestID)
        }
        let holder = Payload()
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            let count = holder.factoryCalls.withLock { calls in calls += 1; return calls }
            Self.logger.notice("QL_REPLY_PROBE factory id=\(requestID) call=\(count) main=\(Thread.isMainThread)")
            return holder.html
        }
        reply.title = "MostlyText static Quick Look probe"
        reply.stringEncoding = .utf8
        reply.attachments = ["control": QLPreviewReplyAttachment(data: holder.png, contentType: .png)]
        Self.logger.notice("QL_REPLY_PROBE replied id=\(requestID) html=\(holder.html.count) png=\(holder.png.count)")
        return reply
    }

    private func readSelectedAndCheckSibling(_ file: URL) throws {
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard descriptor >= 0 else {
            Self.logger.error("QL_REPLY_PROBE selected-open-refused errno=\(errno)")
            throw ProbeError.refused
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= 2 * 1024 * 1024
        else { throw ProbeError.refused }
        var bytes = [UInt8](repeating: 0, count: Int(metadata.st_size))
        var readCount = 0
        while readCount < bytes.count {
            let offset = readCount
            let count = bytes.withUnsafeMutableBytes { read(
                descriptor,
                $0.baseAddress?.advanced(by: offset),
                $0.count - offset
            ) }
            guard count > 0 else { throw ProbeError.refused }
            readCount += count
        }
        let expected = file.lastPathComponent == "mostlytext-ql-reply-static.md"
            ? "# Hosted Quick Look fixture\n"
            : RendererRequest.source(large: file.lastPathComponent == "mostlytext-ql-d2-large.md")
        guard readCount == bytes.count,
              Data(bytes) == Data(expected.utf8)
        else { throw ProbeError.refused }
        Self.logger.notice("QL_REPLY_PROBE selected-read bytes=\(readCount)")
        // This sibling is generated by the hosted probe; never read its contents.
        let neighbor = file.deletingLastPathComponent().appendingPathComponent("ql-probe-neighbor.md")
        let neighborDescriptor = open(neighbor.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY)
        let neighborError = neighborDescriptor < 0 ? errno : 0
        if neighborDescriptor >= 0 {
            close(neighborDescriptor)
        }
        Self.logger.notice("QL_REPLY_PROBE sibling-open-admitted=\(neighborDescriptor >= 0) errno=\(neighborError)")
    }

    private final class Payload: Sendable {
        let factoryCalls = Mutex(0)
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src cid:; base-uri 'none'">
        <h1>MOSTLYTEXT_QL_REPLY_STATIC_20261107</h1>
        <p>Static local reply, generated on the disposable hosted runner.</p>
        <img src="cid:control" width="96" height="96" alt="Static color control">
        """.utf8)
        /// Original PNG from the previously compiled API control, not brand artwork.
        let png = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
            0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x50, 0x72, 0x49, 0xFB,
            0x0F, 0x00, 0x03, 0x24, 0x01, 0xCC, 0x62, 0x67, 0x48, 0x94, 0x00, 0x00,
            0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ])
    }

    enum ProbeError: Error { case refused }
}

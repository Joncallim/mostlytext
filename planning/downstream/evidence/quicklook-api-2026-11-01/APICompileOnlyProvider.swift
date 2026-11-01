import Foundation
import QuickLookUI

/// Compile-only SDK witness. This is a library with no extension bundle,
/// application entry point, registration metadata or production file reader.
final class APICompileOnlyProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for _: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src cid:; base-uri 'none'">
        <h1>MostlyText Quick Look API control</h1><img src="cid:control" alt="Static color control">
        """.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            html
        }
        reply.title = "MostlyText Quick Look API control"
        reply.stringEncoding = .utf8
        // Original synthetic 1 x 1 RGBA fixture, generated with zlib/PNG chunks.
        let png =
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNQckn7DwADJAHMYmdIlAAAAABJRU5ErkJggg=="
            ) ??
            Data()
        reply.attachments = ["control": QLPreviewReplyAttachment(data: png, contentType: .png)]
        return reply
    }
}

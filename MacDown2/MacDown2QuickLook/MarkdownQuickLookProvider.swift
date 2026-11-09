import Foundation
import QuickLookSource
import QuickLookUI

/// The first production Quick Look slice publishes only a passive source view.
/// Derived rendering remains behind the bounded-worker acceptance gate.
final class MarkdownQuickLookProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let selectedURL = request.fileURL
        let html = try await Task.detached(priority: .userInitiated) {
            try QuickLookSourceFallback.replyHTML(for: selectedURL)
        }.value
        let payload = Payload(html: html)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            payload.html
        }
        reply.stringEncoding = .utf8
        return reply
    }

    private final class Payload: Sendable {
        let html: Data

        init(html: Data) {
            self.html = html
        }
    }
}

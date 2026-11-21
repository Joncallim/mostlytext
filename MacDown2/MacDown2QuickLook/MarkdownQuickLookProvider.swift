import Foundation
import OSLog
import QuickLookSource
import QuickLookUI

private let providerLogger = Logger(subsystem: "app.mostlytext.quicklook.worker", category: "provider")

/// Publishes the bounded worker's passive Markdown and derived-content reply.
final class MarkdownQuickLookProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let selectedURL = request.fileURL
        let selected = try await QuickLookSelectedFileOpener.open(selectedURL)
        guard let html = await QuickLookWorkerClient.renderSource(selected) else {
            throw QuickLookSourceError.readFailed
        }
        try Task.checkCancellation()
        let hasSVG = html.range(of: Data("<svg".utf8)) != nil
        providerLogger.notice("Provider received reply bytes: \(html.count), SVG: \(hasSVG)")
        let payload = Payload(html: html)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            providerLogger.notice("Quick Look requested reply bytes: \(payload.html.count), SVG: \(hasSVG)")
            return payload.html
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

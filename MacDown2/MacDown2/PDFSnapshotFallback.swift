import AppKit
import CoreGraphics
import Foundation
import WebKit

/// A bounded local fallback when WKWebView's AppKit print operation completes
/// without a usable PDF. Only an already paper-sized vector result is safe to
/// publish: clipping a taller source page duplicates search text and can hide
/// glyphs already cut off at WebKit's vector-page boundary.
@MainActor
enum PDFSnapshotFallback {
    static let maxPages = 256
    static let captureTimeout: Duration = .seconds(30)

    /// Keep the established layout width while fitting one real printable page.
    /// A taller arbitrary viewport would turn unused canvas into a blank PDF slice.
    static func viewportSize(for info: NSPrintInfo) -> NSSize? {
        let values = [
            info.paperSize.width, info.paperSize.height, info.leftMargin,
            info.rightMargin, info.topMargin, info.bottomMargin,
        ]
        guard values.allSatisfy(\.isFinite) else { return nil }
        return viewportSize(
            printableWidth: info.paperSize.width - info.leftMargin - info.rightMargin,
            printableHeight: info.paperSize.height - info.topMargin - info.bottomMargin
        )
    }

    static func viewportSize(printableWidth: CGFloat, printableHeight: CGFloat) -> NSSize? {
        guard printableWidth.isFinite, printableHeight.isFinite,
              printableWidth > 0, printableHeight > 0 else { return nil }
        let height = floor(printableHeight * 794 / printableWidth)
        guard height.isFinite, (1 ... 16384).contains(height) else { return nil }
        return NSSize(width: 794, height: height)
    }

    static func render(
        webView: WKWebView,
        printInfo: NSPrintInfo,
        maxBytes: Int
    ) async throws -> Data {
        let waiter = PDFSnapshotWaiter()
        let data = try await waiter.capture(webView, timeout: captureTimeout)
        try Task.checkCancellation()
        return try paginate(data, printInfo: printInfo, maxBytes: maxBytes)
    }

    static func paginate(_ data: Data, printInfo: NSPrintInfo, maxBytes: Int) throws -> Data {
        guard !data.isEmpty, data.count <= maxBytes,
              let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages > 0
        else { throw FallbackError.invalidSnapshot }

        let paperSize = printInfo.paperSize
        let printableWidth = paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let printableHeight = paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        guard printableWidth.isFinite, printableHeight.isFinite,
              printableWidth > 0, printableHeight > 0
        else { throw FallbackError.invalidGeometry }

        let pages = try sourcePages(in: document)
        // An ordinary AppKit print result is already page-sized. WebKit's
        // createPDF fallback can also return several 14,400-point pages;
        // their count alone does not establish usable paper geometry.
        if pages.allSatisfy({ page in
            let box = page.getBoxRect(.mediaBox)
            return abs(box.width - paperSize.width) < 1 && abs(box.height - paperSize.height) < 1
        }) {
            return data
        }
        // Re-embedding a tall source page under a paper clip repeats its full
        // text stream on every output page. PDF search then sees duplicates,
        // and WebKit may already have clipped glyphs at a 14,400-point seam.
        // Only a direct paper-sized vector PDF can be published faithfully.
        throw FallbackError.invalidGeometry
    }

    private static func sourcePages(in document: CGPDFDocument) throws -> [CGPDFPage] {
        guard document.numberOfPages <= maxPages else { throw FallbackError.tooManyPages }
        return try (1 ... document.numberOfPages).map { index in
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw FallbackError.invalidSnapshot }
            let box = page.getBoxRect(.mediaBox)
            guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0
            else { throw FallbackError.invalidGeometry }
            return page
        }
    }

    enum FallbackError: LocalizedError {
        case invalidSnapshot
        case invalidGeometry
        case tooManyPages
        case tooLarge
        case cannotWrite
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidSnapshot: String(localized: "WebKit did not produce a readable PDF snapshot.")
            case .invalidGeometry: String(localized: "WebKit produced a PDF with unsupported page dimensions.")
            case .tooManyPages: String(
                    localized: "The document needs more PDF pages than this export can safely create."
                )
            case .tooLarge: String(localized: "The PDF would exceed the current export size limit.")
            case .cannotWrite: String(localized: "The PDF could not be written to a temporary file.")
            case .timedOut: String(localized: "WebKit took too long to prepare the PDF.")
            }
        }

        var recoverySuggestion: String? {
            String(localized: "The prior output was left unchanged. Try a shorter document or export as HTML.")
        }
    }
}

@MainActor
private final class PDFSnapshotWaiter {
    private var continuation: CheckedContinuation<Data, Error>?

    func capture(_ webView: WKWebView, timeout: Duration) async throws -> Data {
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(PDFSnapshotFallback.FallbackError.timedOut))
        }
        defer { watchdog.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled {
                    finish(.failure(CancellationError()))
                } else {
                    webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                        self?.finish(result)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

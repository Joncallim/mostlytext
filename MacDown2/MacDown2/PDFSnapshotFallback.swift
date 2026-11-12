import AppKit
import CoreGraphics
import Foundation
import PDFKit
import WebKit

/// A bounded local fallback when WKWebView's AppKit print operation completes
/// without a usable PDF. WebKit supplies vector PDF content; Core Graphics
/// divides its tall page into paper-sized pages without rasterizing text.
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

        // WebKit normally creates one tall page. Preserve an already-paged
        // output without drawing it a second time.
        if document.numberOfPages > 1 {
            guard document.numberOfPages <= maxPages else { throw FallbackError.tooManyPages }
            return data
        }

        guard let sourcePage = document.page(at: 1) else { throw FallbackError.invalidSnapshot }
        let sourceBox = sourcePage.getBoxRect(.mediaBox)
        let paperSize = printInfo.paperSize
        let printableWidth = paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let printableHeight = paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        guard sourceBox.width.isFinite, sourceBox.height.isFinite,
              sourceBox.width > 0, sourceBox.height > 0,
              printableWidth.isFinite, printableHeight.isFinite,
              printableWidth > 0, printableHeight > 0
        else { throw FallbackError.invalidGeometry }

        let scale = printableWidth / sourceBox.width
        let sliceHeight = printableHeight / scale
        let ranges = try pageRanges(
            in: data,
            sourceBox: sourceBox,
            sliceHeight: sliceHeight,
            scale: scale
        )

        // CGContext may embed the source page as a form on each output page.
        // Bound this conservative upper estimate before creating any file.
        let estimated = data.count.multipliedReportingOverflow(by: ranges.count)
        guard !estimated.overflow, estimated.partialValue <= maxBytes else {
            throw FallbackError.tooLarge
        }

        let output = NSMutableData()
        var paperBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &paperBox, nil)
        else { throw FallbackError.cannotWrite }

        let geometry = SliceGeometry(sourceBox: sourceBox, scale: scale, sliceHeight: sliceHeight, ranges: ranges)
        try drawPages(in: context, from: sourcePage, printInfo: printInfo, geometry: geometry)
        context.closePDF()

        guard output.length > 0, output.length <= maxBytes
        else { throw FallbackError.tooLarge }
        return output as Data
    }

    private struct SliceGeometry {
        let sourceBox: CGRect
        let scale: CGFloat
        let sliceHeight: CGFloat
        let ranges: [ClosedRange<CGFloat>]
    }

    /// Move a cut just above any line it would bisect. `createPDF` supplies a
    /// single tall PDF page, so print CSS cannot paginate it for us. Inspect
    /// only a narrow band around each proposed cut rather than materializing
    /// selections for the entire document.
    private static func pageRanges(
        in data: Data,
        sourceBox: CGRect,
        sliceHeight: CGFloat,
        scale: CGFloat
    ) throws -> [ClosedRange<CGFloat>] {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else {
            throw FallbackError.invalidSnapshot
        }
        let safety = 3 / scale
        var top = sourceBox.maxY
        var ranges: [ClosedRange<CGFloat>] = []
        while top > sourceBox.minY {
            try Task.checkCancellation()
            guard ranges.count < maxPages else { throw FallbackError.tooManyPages }
            let targetBottom = max(sourceBox.minY, top - sliceHeight)
            var bottom = targetBottom
            if targetBottom > sourceBox.minY {
                let band = CGRect(
                    x: sourceBox.minX,
                    y: targetBottom - safety,
                    width: sourceBox.width,
                    height: 2 * safety
                )
                if let selection = page.selection(for: band) {
                    for line in selection.selectionsByLine() {
                        let bounds = line.bounds(for: page)
                        if bounds.minY < targetBottom + safety, bounds.maxY > targetBottom - safety {
                            bottom = max(bottom, bounds.maxY + safety)
                        }
                    }
                }
            }
            // An unusually tall element cannot be moved indefinitely; fail
            // rather than create near-empty pages or loop without progress.
            guard bottom <= top - min(sliceHeight / 2, top - sourceBox.minY) else {
                throw FallbackError.invalidGeometry
            }
            ranges.append(bottom ... top)
            top = bottom
        }
        return ranges
    }

    private static func drawPages(
        in context: CGContext,
        from sourcePage: CGPDFPage,
        printInfo: NSPrintInfo,
        geometry: SliceGeometry
    ) throws {
        let printableWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let printableHeight = geometry.sliceHeight * geometry.scale
        for range in geometry.ranges {
            try Task.checkCancellation()
            context.beginPDFPage(nil)
            context.saveGState()
            let usedHeight = (range.upperBound - range.lowerBound) * geometry.scale
            context.clip(to: CGRect(
                x: printInfo.leftMargin,
                y: printInfo.bottomMargin + printableHeight - usedHeight,
                width: printableWidth,
                height: usedHeight
            ))
            context.translateBy(x: printInfo.leftMargin, y: printInfo.bottomMargin + printableHeight)
            context.scaleBy(x: geometry.scale, y: geometry.scale)
            context.translateBy(
                x: -geometry.sourceBox.minX,
                y: -range.upperBound
            )
            context.drawPDFPage(sourcePage)
            context.restoreGState()
            context.endPDFPage()
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

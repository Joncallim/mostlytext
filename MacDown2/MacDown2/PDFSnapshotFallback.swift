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
        guard let readable = PDFDocument(data: data), readable.pageCount == pages.count
        else { throw FallbackError.invalidSnapshot }
        let slices = try paperSlices(pages, readable: readable,
                                     printableWidth: printableWidth, printableHeight: printableHeight)

        return try render(slices, sourceBytes: data.count, printInfo: printInfo, maxBytes: maxBytes)
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

    private static func paperSlices(
        _ pages: [CGPDFPage], readable: PDFDocument,
        printableWidth: CGFloat, printableHeight: CGFloat
    ) throws -> [PageSlice] {
        var slices: [PageSlice] = []
        var count = 0
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            guard let readablePage = readable.page(at: index) else { throw FallbackError.invalidSnapshot }
            let box = page.getBoxRect(.mediaBox)
            let scale = printableWidth / box.width
            let sliceHeight = printableHeight / scale
            guard scale.isFinite, scale > 0, sliceHeight.isFinite, sliceHeight > 0
            else { throw FallbackError.invalidGeometry }
            let ranges = try pageRanges(on: readablePage, sourceBox: box,
                                        sliceHeight: sliceHeight, scale: scale)
            guard count <= maxPages - ranges.count else { throw FallbackError.tooManyPages }
            count += ranges.count
            slices.append(PageSlice(page: page, geometry: SliceGeometry(
                sourceBox: box, scale: scale, sliceHeight: sliceHeight, ranges: ranges
            )))
        }
        return slices
    }

    private static func render(
        _ slices: [PageSlice], sourceBytes: Int, printInfo: NSPrintInfo, maxBytes: Int
    ) throws -> Data {
        // CGContext may embed the source page as a form on each output page.
        // Bound this conservative upper estimate before creating any file.
        let pageCount = slices.reduce(0) { $0 + $1.geometry.ranges.count }
        let estimated = sourceBytes.multipliedReportingOverflow(by: pageCount)
        guard !estimated.overflow, estimated.partialValue <= maxBytes else {
            throw FallbackError.tooLarge
        }

        let output = NSMutableData()
        var paperBox = CGRect(origin: .zero, size: printInfo.paperSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &paperBox, nil)
        else { throw FallbackError.cannotWrite }

        for slice in slices {
            try drawPages(in: context, from: slice.page, printInfo: printInfo, geometry: slice.geometry)
        }
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

    private struct PageSlice {
        let page: CGPDFPage
        let geometry: SliceGeometry
    }

    /// Move a cut just above any line it would bisect. `createPDF` supplies a
    /// single tall PDF page, so print CSS cannot paginate it for us. Inspect
    /// only a narrow band around each proposed cut rather than materializing
    /// selections for the entire document.
    private static func pageRanges(
        on page: PDFPage, sourceBox: CGRect, sliceHeight: CGFloat, scale: CGFloat
    ) throws -> [ClosedRange<CGFloat>] {
        // Probe a wider band than the final displacement. A narrow PDFKit
        // selection can miss the edge of a glyph near the proposed cut;
        // moving by the entire probe width can land inside the next line.
        let safety = 24 / scale
        let padding = 3 / scale
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
                            bottom = max(bottom, bounds.maxY + padding)
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

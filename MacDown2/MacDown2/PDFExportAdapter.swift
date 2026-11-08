import AppKit
import CoreGraphics
import ExportService
import Foundation
import PDFKit
import WebKit

/// The isolated PDF adapter (issue #49 Slice 4).
///
/// It does not re-render Markdown. It loads the same self-contained HTML the
/// HTML exporter produces into a locked-down, ephemeral `WKWebView`, prints it
/// through `WKWebView.printOperation(with:)` / `NSPrintOperation` (with the
/// system `NSPrintInfo` supplying geometry), and then validates the result with
/// PDFKit before atomically promoting it into place.
///
/// The WebKit view is locked down: JavaScript is disabled, and a restrictive
/// Content-Security-Policy is injected so authored raw HTML cannot reach the
/// network — the export remains local and offline.
@MainActor
enum PDFExportAdapter {
    /// How long the page is given to lay out before the print pass is abandoned.
    /// `loadHTMLString` with no base URL cannot reach the network, so anything
    /// beyond this is a stall, not slow loading — and a stall must not leave the
    /// user with a menu that never comes back.
    private static let loadTimeout: Duration = .seconds(30)
    /// Provisional output admission before allocating Data/PDFKit objects. The
    /// release memory calibration must confirm or revise this separate PDF cap.
    private nonisolated static let maxPDFBytes = 256 * 1024 * 1024
    /// Preview rasterization is only an admission check; the original vector
    /// PDF is published unchanged. Bound the page work and scratch memory.
    private static let maxValidationPages = 1024
    private static let validationSide = 256

    static func export(_ prepared: PreparedExportDocument, to url: URL,
                       lease: ExportLifetimeLease = ExportLifetimeLease(),
                       admission: ExportDestinationAdmission? = nil,
                       runPrint: @MainActor (NSPrintOperation) -> Bool = { $0.run() }) async throws {
        try lease.checkActive()
        let authorization = try admission ?? ExportDestinationAdmission(capturing: url)
        try authorization.checkTarget(url)
        // Base64-encoding every embedded image is the most expensive step in a
        // PDF export; it is done off the main actor so the app stays responsive.
        let html = try await hardenedHTML(from: prepared)
        let sourceHasContent = !prepared.bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        try await exportHTML(html, to: url, sourceHasContent: sourceHasContent,
                             lease: lease, admission: authorization, runPrint: runPrint)
    }

    /// Disabled opt-in consumer: WebKit receives exactly the accepted UTF-8
    /// bytes, and the caller's lifetime lease still guards final publication.
    static func export(_ validated: ValidatedExportHTML, to url: URL,
                       lease: ExportLifetimeLease) async throws {
        let admission = try ExportDestinationAdmission(capturing: url)
        let html = try validatedHTMLForWebKit(validated, to: url)
        // ValidatedExportHTML does not expose the source body. Fail closed on
        // an unmarked PDF until that path's activation contract defines how an
        // intentionally empty document should be represented.
        try await exportHTML(html, to: url, sourceHasContent: true, lease: lease, admission: admission)
    }

    static func validatedHTMLForWebKit(_ validated: ValidatedExportHTML, to url: URL) throws -> String {
        guard validated.isForPDF(at: url),
              let html = String(data: validated.utf8, encoding: .utf8),
              Data(html.utf8) == validated.utf8 else {
            throw ExportError.validatedPublicationRejected
        }
        return html
    }

    private static func exportHTML(_ html: String, to url: URL, sourceHasContent: Bool,
                                   lease: ExportLifetimeLease?, admission: ExportDestinationAdmission,
                                   runPrint: @MainActor (NSPrintOperation) -> Bool = { $0.run() }) async throws {
        try lease?.checkActive()

        let printURL = temporaryURL(nextTo: url)
        let snapshotURL = temporaryURL(nextTo: url)
        defer {
            try? FileManager.default.removeItem(at: printURL)
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        let info = printInfo(savingTo: printURL)
        guard let size = PDFSnapshotFallback.viewportSize(for: info) else {
            throw PDFExportError.printConfigurationFailed
        }
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: lockedConfiguration())
        let delegate = PDFNavigationDelegate()
        webView.navigationDelegate = delegate

        // Load failures surface as themselves: they already carry prose the
        // user can act on, and wrapping them as a write failure would misname
        // what went wrong.
        try await delegate.load(html, in: webView, timeout: loadTimeout)
        try Task.checkCancellation()
        try lease?.checkActive()

        try admission.checkCurrent()
        let operation = try configuredOperation(for: webView, savingTo: printURL, printInfo: info)
        let didPrint = runPrint(operation)
        // `run()` can occupy the main thread. Cancellation or lease revocation
        // already recorded when it returns must win before PDFKit reads the
        // scratch file or the existing destination can be replaced.
        try Task.checkCancellation()
        try lease?.checkActive()
        guard didPrint else {
            throw PDFExportError.printOperationFailed
        }

        var output = try await validatedPDFBytes(at: printURL, admission: admission, sourceHasContent: sourceHasContent)
        if output == nil {
            // A successful print operation can still write no marks at all.
            // Keep its broken output isolated and ask WebKit for a local vector
            // snapshot, which is divided into ordinary paper-sized pages.
            try Task.checkCancellation()
            try lease?.checkActive()
            try admission.checkCurrent()
            try await PDFSnapshotFallback.render(
                webView: webView,
                printInfo: operation.printInfo,
                to: snapshotURL,
                maxBytes: maxPDFBytes
            )
            output = try await validatedPDFBytes(
                at: snapshotURL, admission: admission, sourceHasContent: sourceHasContent
            )
        }
        try Task.checkCancellation()
        try lease?.checkActive()

        guard let output else { throw PDFExportError.invalidPDFOutput }
        let publicationLease = lease ?? ExportLifetimeLease()
        try await io { try admission.publish(output, lease: publicationLease) }
    }

    private static func validatedPDFBytes(
        at url: URL, admission: ExportDestinationAdmission, sourceHasContent: Bool
    ) async throws -> Data? {
        let data: Data?
        do {
            data = try await io { try admission.readGeneratedFile(at: url, maxBytes: maxPDFBytes) }
        } catch ExportError.budgetExceeded {
            throw PDFExportError.pdfTooLarge
        }
        guard let data else { return nil }
        return normalizedPrintableData(data, sourceHasContent: sourceHasContent)
    }

    /// Detached file I/O has an explicit cancellation bridge back to its owner.
    /// PDFKit and the print operation remain on their existing main-actor path.
    private nonisolated static func io<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func configuredOperation(
        for webView: WKWebView, savingTo url: URL, printInfo: NSPrintInfo
    ) throws -> NSPrintOperation {
        let operation = webView.printOperation(with: printInfo)
        // Reapply the same configured geometry used before WebKit layout;
        // the operation factory need not retain the incoming NSPrintInfo object.
        operation.printInfo = printInfo
        guard operation.printInfo.jobDisposition == .save,
              operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL == url
        else { throw PDFExportError.printConfigurationFailed }
        operation.showsPrintPanel = false
        // Apple documents that PDF/EPS generation never displays AppKit's
        // print progress panel, regardless of this flag. `run()` is still
        // synchronous; a separate whole-export progress and print-time policy
        // is required before the issue's user-facing criterion can close.
        operation.showsProgressPanel = true
        // WebKit's print view is distinct from the WKWebView. Give it the
        // loaded view's geometry before AppKit starts pagination.
        guard let printView = operation.view else { throw PDFExportError.printOperationFailed }
        printView.frame = webView.bounds
        printView.layoutSubtreeIfNeeded()
        return operation
    }

    private static func lockedConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = pagePreferences
        return configuration
    }

    /// The self-contained HTML with a restrictive CSP so raw authored HTML
    /// cannot fetch remote resources during the print pass.
    ///
    /// The policy is handed to the template as head content rather than
    /// substituted into the rendered string afterwards: a string rewrite would
    /// silently stop applying if the template's whitespace ever changed, and a
    /// security control that can vanish without failing is not a control.
    nonisolated static func hardenedHTML(from prepared: PreparedExportDocument) async throws -> String {
        let csp = "<meta http-equiv=\"Content-Security-Policy\" content=\""
            + "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
            + "img-src data:; media-src data:; font-src data:; connect-src 'none'; "
            + "object-src 'none'; form-action 'none'; base-uri 'none';\">"
        return try ExportHTMLWriter.selfContainedHTML(from: prepared, additionalHead: csp)
    }

    /// Configure the system key before WebKit copies the print info into its operation.
    static func printInfo(savingTo url: URL) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        return info
    }

    static func configure(_ operation: NSPrintOperation, savingTo url: URL) {
        operation.printInfo = printInfo(savingTo: url)
    }

    /// Validate immutable bytes once; the same accepted value is published.
    /// Normalization never rewrites an unverified printer scratch pathname.
    static func normalizedPrintableData(_ data: Data, sourceHasContent: Bool) -> Data? {
        guard !data.isEmpty, data.count <= maxPDFBytes,
              let checked = PDFCrossReferenceIntegrity.normalized(data),
              isPrintablePDF(checked, sourceHasContent: sourceHasContent) else { return nil }
        return checked
    }

    /// A syntactically valid PDF can still contain only empty graphics-state
    /// wrappers on every page. Keep that output away from the chosen filename.
    static func isPrintablePDF(_ data: Data, sourceHasContent: Bool) -> Bool {
        guard data.count <= maxPDFBytes,
              let document = PDFDocument(data: data),
              document.pageCount > 0,
              document.pageCount <= maxValidationPages else { return false }
        guard sourceHasContent else { return true }
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index)?.pageRef else { continue }
            if pageHasVisibleInk(page) {
                return true
            }
        }
        return false
    }

    private static func pageHasVisibleInk(_ page: CGPDFPage) -> Bool {
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0,
              box.width <= 14400, box.height <= 14400 else { return false }

        let side = validationSide
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.concatenate(page.getDrawingTransform(
                .cropBox,
                rect: CGRect(x: 0, y: 0, width: side, height: side),
                rotate: 0,
                preserveAspectRatio: true
            ))
            context.drawPDFPage(page)

            let raw = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: raw.count, by: 4).contains { index in
                raw[index] < 248 || raw[index + 1] < 248 || raw[index + 2] < 248
            }
        }
    }

    static func temporaryURL(nextTo url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).\(UUID().uuidString).tmp.pdf")
    }

    enum PDFExportError: Error, LocalizedError {
        case invalidPDFOutput
        case noPDFOutput
        case pdfTooLarge
        case printConfigurationFailed
        case printOperationFailed
        case pageLoadTimedOut

        var errorDescription: String? {
            switch self {
            case .invalidPDFOutput: String(localized: "The printed document was not a readable PDF.")
            case .noPDFOutput: String(localized: "The macOS print system did not write a PDF.")
            case .pdfTooLarge: String(localized: "The PDF exceeds the current export size limit.")
            case .printConfigurationFailed: String(
                    localized: "The macOS print system did not accept the PDF destination."
                )
            case .printOperationFailed: String(localized: "The macOS print system could not produce the PDF.")
            case .pageLoadTimedOut: String(localized: "Laying the document out for printing took too long.")
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidPDFOutput, .noPDFOutput, .pdfTooLarge, .printConfigurationFailed, .printOperationFailed:
                String(localized: "Try exporting as HTML, or print the document from the preview.")
            case .pageLoadTimedOut:
                String(localized: "Try again, or split very large documents before exporting.")
            }
        }
    }
}

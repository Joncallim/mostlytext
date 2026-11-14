import AppKit
import CoreGraphics
import CoreText
import ExportService
import Foundation
@testable import MacDown2
import PDFKit
import Testing
import Themes

/// Genuine controls for E12's outstanding PDF-pagination gap (`RELEASE_EVIDENCE.md`):
/// `PDFExportAdapter`
/// had real print-CSS pagination rules (`ExportStylesheetTests` already
/// confirmed the CSS text itself contains `page-break-inside: avoid`) but no
/// automated coverage of the actual, real print pipeline — this drives the
/// genuine `WKWebView` → `NSPrintOperation` → `PDFKit` path end to end, not a
/// mock of any piece of it.
///
/// The two real print-operation tests remain disabled in ordinary runs because
/// historical local test hosts lacked required OS services and could hang.
/// `PDF_PAGINATION_PROBE` enables them only for the dedicated hosted macOS 26
/// qualification, whose owned executor bounds the run and retains diagnostics.
/// Compile-only and vector-fallback tests do not replace that execution evidence.
@Suite(.serialized)
@MainActor
struct PDFExportAdapterTests {
    private nonisolated static var nativePaginationEnabled: Bool {
        #if PDF_PAGINATION_PROBE
            true
        #else
            false
        #endif
    }

    @Test func tallVectorSnapshotIsRefusedBeforePublication() throws {
        let source = try makeTallTextPDF()
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 100, height: 100)
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0

        do {
            _ = try PDFSnapshotFallback.paginate(source, printInfo: info, maxBytes: 1_000_000)
            Issue.record("Tall vector source must not be published with duplicate searchable text")
        } catch PDFSnapshotFallback.FallbackError.invalidGeometry {
            // Direct paper-sized AppKit print is the qualified vector route.
        }
    }

    @Test func tallVectorWithHeadingAtPaperCutIsRefused() throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 300)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 18, nil)
        let fontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "CUT", attributes: [fontKey: font]))
        context.textPosition = CGPoint(x: 10, y: 197)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 100, height: 100)
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        do {
            _ = try PDFSnapshotFallback.paginate(data as Data, printInfo: info, maxBytes: 1_000_000)
            Issue.record("Tall vector source must not be republished under paper clipping")
        } catch PDFSnapshotFallback.FallbackError.invalidGeometry {
            // The source page remains in scratch and no destination is replaced.
        }
    }

    @Test func printDestinationIsConfiguredBeforeTheOperationStarts() throws {
        let scratch = try ExportPrintScratch()
        defer { try? scratch.retire() }
        let url = scratch.url
        let info = PDFExportAdapter.printInfo(savingTo: url)

        #expect(url.pathExtension == "pdf")
        #expect(info.jobDisposition == .save)
        #expect(info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL == url)

        PDFViewportChecks.verify(info: info)

        let operation = NSPrintOperation(
            view: NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
            printInfo: NSPrintInfo()
        )
        PDFExportAdapter.configure(operation, savingTo: url)
        #expect(operation.printInfo.jobDisposition == .save)
        #expect(operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL == url)
    }

    @Test func contentlessPDFIsRejectedForNonemptyDocument() throws {
        #expect(try !PDFExportAdapter.isPrintablePDF(makePDF(painted: false), sourceHasContent: true))
        #expect(try PDFExportAdapter.isPrintablePDF(makePDF(painted: true), sourceHasContent: true))
        #expect(try PDFExportAdapter.isPrintablePDF(makePDF(painted: false), sourceHasContent: false))
    }

    @Test func graphicsSetupAndEmptyTextDoNotCountAsPrintedContent() {
        // These are explicit PDF operators. CGContext may optimize them away
        // when no paint follows, which would leave the old byte heuristic
        // untested rather than prove it rejects valid-but-empty streams.
        let content = "q 1 0 0 1 9 11 cm BT ET 2 2 m 30 30 l Q"
        let pdf = makeRawPDF(contentStream: content)
        #expect(PDFDocument(data: pdf)?.pageCount == 1)
        #expect(!PDFExportAdapter.isPrintablePDF(pdf, sourceHasContent: true))
    }

    private func makeRawPDF(contentStream: String) -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>",
            "<< /Length \(contentStream.utf8.count) >>\nstream\n\(contentStream)\nendstream",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets = [Int]()
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\n"
        pdf += "startxref\n\(xrefOffset)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    @Test func visibleTextAndVectorOnlyDiagramCountAsPrintedContent() throws {
        #expect(try PDFExportAdapter.isPrintablePDF(makeTallTextPDF(), sourceHasContent: true))

        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(2)
        context.stroke(CGRect(x: 10, y: 10, width: 30, height: 25))
        context.move(to: CGPoint(x: 40, y: 22))
        context.addLine(to: CGPoint(x: 70, y: 60))
        context.strokePath()
        context.endPDFPage()
        context.closePDF()

        #expect(PDFExportAdapter.isPrintablePDF(data as Data, sourceHasContent: true))
        #expect(PDFDocument(data: data as Data)?.page(at: 0)?.string?.isEmpty != false)
    }

    private func makePDF(painted: Bool) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        if painted {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 10, y: 10, width: 25, height: 25))
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func makePrintWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func makeTallTextPDF() throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 300)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let fontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
        context.beginPDFPage(nil)
        for (label, offsetY) in [("TOP", 260.0), ("MIDDLE", 160.0), ("BOTTOM", 60.0)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [fontKey: font]))
            context.textPosition = CGPoint(x: 10, y: offsetY)
            CTLineDraw(line, context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @Test func hardenedHTMLRetainsThePDFPolicy() async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Printable\n\nA short document.\n", sourceGeneration: 1, theme: BundledThemes.light),
            target: .pdf(url: FileManager.default.temporaryDirectory.appendingPathComponent("print.pdf"))
        )
        let html = try await PDFExportAdapter.hardenedHTML(from: prepared)
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("html { scrollbar-width: none !important; }"))
        #expect(html.contains("A short document."))
    }

    /// A document long enough that it cannot possibly fit on one page under
    /// any reasonable page size, with several fenced code blocks — the
    /// content `structural.css`'s `page-break-inside: avoid` rule targets —
    /// interspersed among the filler so a page break landing badly would be
    /// visible as a real, addressable defect if this ever regresses.
    private static func longMarkdown() -> String {
        var text = "# PDF Pagination Torture Document\n\n"
        for section in 1 ... 25 {
            text += "## Section \(section)\n\n"
            text += String(
                repeating: "This is representative body text used to force real, multi-page pagination. ",
                count: 12
            )
            text += "\n\n"
            if section.isMultiple(of: 5) {
                text += "```swift\nfunc section\(section)() -> Int {\n    return \(section) * 2\n}\n```\n\n"
            }
        }
        return text
    }

    @Test(.enabled(if: Self.nativePaginationEnabled, "requires the bounded hosted PDF pagination qualification"))
    func exportingALongDocumentProducesARealMultiPagePDF() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFExportAdapterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = directory.appendingPathComponent("out.pdf")
        let prepared = try await ExportService.prepare(
            ExportRequest(text: Self.longMarkdown(), sourceGeneration: 1, theme: BundledThemes.light),
            target: .pdf(url: pdfURL)
        )

        let window = makePrintWindow()
        defer { window.orderOut(nil); window.close() }
        try await PDFExportAdapter.export(prepared, to: pdfURL, modalWindow: window)

        let data = try Data(contentsOf: pdfURL)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1, "a 25-section document must not collapse onto a single PDF page")

        // The document's own text must survive the print pass, not just its
        // page count — proves pagination didn't happen at the cost of content.
        let allText = (0 ..< document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()
        #expect(allText.contains("Section 1"))
        #expect(allText.contains("Section 25"))
        #expect(allText.contains("func section25"))
    }

    @Test(.enabled(if: Self.nativePaginationEnabled, "requires the bounded hosted PDF pagination qualification"))
    func exportedPDFReplacesAnyExistingFileAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFExportAdapterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = directory.appendingPathComponent("out.pdf")
        try Data("not a real pdf".utf8).write(to: pdfURL)

        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: "# Short\n\nJust one short document.\n",
                sourceGeneration: 1,
                theme: BundledThemes.light
            ),
            target: .pdf(url: pdfURL)
        )
        let window = makePrintWindow()
        defer { window.orderOut(nil); window.close() }
        try await PDFExportAdapter.export(prepared, to: pdfURL, modalWindow: window)

        let data = try Data(contentsOf: pdfURL)
        let document = try #require(PDFDocument(data: data), "the stale placeholder must be replaced with a real PDF")
        #expect(document.pageCount == 1, "unused viewport height must not append a blank page")
        #expect(document.string?.contains("Just one short document.") == true)
        let pdfNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".pdf") }
        #expect(pdfNames == ["out.pdf"], "the print operation must leave no PDF scratch beside the chosen output")
    }
}

@MainActor
private enum PDFViewportChecks {
    static func verify(info: NSPrintInfo) {
        for (width, height, expected) in [(100.0, 100.0, 794.0), (200, 100, 397), (100, 200, 1588)] {
            #expect(PDFSnapshotFallback.viewportSize(printableWidth: width, printableHeight: height)
                == NSSize(width: 794, height: expected))
        }
        for invalid in [CGFloat.zero, -1, .nan, .infinity, -.infinity] {
            #expect(PDFSnapshotFallback.viewportSize(printableWidth: invalid, printableHeight: 100) == nil)
            #expect(PDFSnapshotFallback.viewportSize(printableWidth: 100, printableHeight: invalid) == nil)
        }
        #expect(PDFSnapshotFallback.viewportSize(printableWidth: 1, printableHeight: .greatestFiniteMagnitude) == nil)
        #expect(PDFSnapshotFallback.viewportSize(printableWidth: 10000, printableHeight: 1) == nil)
        let expectedHeight = floor((info.paperSize.height - info.topMargin - info.bottomMargin) * 794
            / (info.paperSize.width - info.leftMargin - info.rightMargin))
        #expect(PDFSnapshotFallback.viewportSize(for: info) == NSSize(width: 794, height: expectedHeight))
        let unusable = NSPrintInfo()
        unusable.leftMargin = unusable.paperSize.width
        unusable.rightMargin = unusable.paperSize.width
        #expect(PDFSnapshotFallback.viewportSize(for: unusable) == nil)
    }
}

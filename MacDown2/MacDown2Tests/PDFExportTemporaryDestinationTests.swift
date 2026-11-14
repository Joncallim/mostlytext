import AppKit
import ExportService
import Foundation
@testable import MacDown2
import PDFKit
import Testing
import Themes

/// Replays the UID-502 private temporary-folder sequence from issue #11.
@Suite("PDF export after HTML in a private temporary folder", .serialized)
@MainActor
struct PDFExportTemporaryDestinationTests {
    private nonisolated static var enabled: Bool {
        #if PDF_PAGINATION_PROBE
            true
        #else
            false
        #endif
    }

    @Test(.enabled(if: enabled, "requires the bounded hosted PDF pagination qualification"))
    func exportingHTMLThenPDFPreservesSourceAndPublishesPDF() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MostlyTextAcceptancePDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("export-canary.md")
        let htmlURL = directory.appendingPathComponent("export-canary.html")
        let pdfURL = directory.appendingPathComponent("export-canary.pdf")
        let source = "# Export canary\n\nPDFCANARY47 **bold** paragraph\n\n- first\n- second\n"
        try Data(source.utf8).write(to: sourceURL)
        let request = ExportRequest(text: source, sourceGeneration: 1, theme: BundledThemes.light)
        let htmlAdmission = try ExportDestinationAdmission(capturing: htmlURL, protecting: [sourceURL])
        _ = try await ExportService.exportHTML(
            request, to: .html(url: htmlURL, mode: .standalone(style: .embedded)),
            admission: htmlAdmission
        )
        #expect(try String(contentsOf: htmlURL, encoding: .utf8).contains("PDFCANARY47"))

        let pdfAdmission = try ExportDestinationAdmission(capturing: pdfURL, protecting: [sourceURL])
        let prepared = try await ExportService.prepare(request, target: .pdf(url: pdfURL))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        try await PDFExportAdapter.export(prepared, to: pdfURL, admission: pdfAdmission, modalWindow: window)
        let pdfBytes = try Data(contentsOf: pdfURL)
        let pdf = try #require(PDFDocument(data: pdfBytes))
        #expect(pdf.pageCount == 1)
        #expect(pdf.string?.contains("PDFCANARY47") == true)
        #expect(try Data(contentsOf: sourceURL) == Data(source.utf8))
    }
}

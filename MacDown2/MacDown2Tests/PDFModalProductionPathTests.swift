import AppKit
import ExportService
import Foundation
@testable import MacDown2
import PDFKit
import Testing
import Themes

/// Hosted-only real print through the ordinary adapter's document-modal path.
@MainActor
struct PDFModalProductionPathTests {
    private nonisolated static var enabled: Bool {
        #if PDF_MODAL_PROBE
            true
        #else
            false
        #endif
    }

    @Test(.enabled(if: enabled, "requires owned hosted PDF modal qualification"))
    func ordinaryAdapterPrintsWhileMainRunLoopAdvances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-modal-production-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("production.pdf")
        let sections = (1 ... 25).map { index in
            "## Section \(index)\n\n" + String(repeating: "Searchable section \(index) text. ", count: 80) + "\n\n"
        }.joined()
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Production modal PDF\n\n" + sections,
                          sourceGeneration: 1, theme: BundledThemes.light),
            target: .pdf(url: destination)
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        var phases: [PDFExportPhase] = []
        let heartbeat = ProductionPDFHeartbeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            heartbeat.tick()
        }
        defer { timer.invalidate() }

        try await PDFExportAdapter.export(
            prepared, to: destination, modalWindow: window,
            onPhase: { phases.append($0) },
            runPrint: { _ in
                Issue.record("The document-modal production path used the synchronous print fallback")
                return false
            }
        )
        #expect(phases == [.preparing, .loading, .printing, .validating, .publishing])
        #expect(!heartbeat.isEmpty)
        let pdf = try #require(PDFDocument(url: destination))
        #expect(pdf.pageCount > 1)
        #expect(pdf.string?.contains("Section 1") == true)
        #expect(pdf.string?.contains("Section 25") == true)
    }
}

private final class ProductionPDFHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks = 0

    func tick() {
        lock.withLock { ticks += 1 }
    }

    var isEmpty: Bool {
        lock.withLock { ticks == 0 }
    }
}

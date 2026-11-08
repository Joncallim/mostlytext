import AppKit
import ExportService
import Foundation
@testable import MacDown2
import Testing
import Themes
import WebKit

@Suite(.serialized)
@MainActor
struct PDFExportCancellationTests {
    private nonisolated static var nativePDFEnabled: Bool {
        #if PDF_PAGINATION_PROBE
            true
        #else
            false
        #endif
    }

    @Test(.enabled(if: Self.nativePDFEnabled, "requires the bounded hosted PDF qualification"))
    func aCancelledNavigationDoesNotWaitForWebKitOrTheThirtySecondWatchdog() async {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let delegate = PDFNavigationDelegate()
        webView.navigationDelegate = delegate

        let load = Task { @MainActor in
            try await delegate.load("<p>Cancelled before loading</p>", in: webView, timeout: .seconds(30))
        }
        let clock = ContinuousClock()
        let started = clock.now
        load.cancel()
        do {
            try await load.value
            Issue.record("a cancelled PDF navigation must not report successful loading")
        } catch is CancellationError {
            // The old implementation allowed WebKit completion to win here.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
        #expect(started.duration(to: clock.now) < .seconds(10), "cancellation must not wait for the watchdog")
    }

    @Test(.enabled(if: Self.nativePDFEnabled, "requires the bounded hosted PDF qualification"))
    func aCancelledPrintResultPreservesTheExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFExportCancellationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("out.pdf")
        let prior = Data("Existing output must survive cancellation".utf8)
        try prior.write(to: destination)
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Cancelled PDF\n\nBody.\n", sourceGeneration: 1, theme: BundledThemes.light),
            target: .pdf(url: destination)
        )
        let lease = ExportLifetimeLease()

        do {
            try await PDFExportAdapter.export(prepared, to: destination, lease: lease, runPrint: { _ in
                // This controlled result exercises the checkpoint after the
                // synchronous call; it does not simulate interrupting AppKit.
                lease.revoke()
                return false
            })
            Issue.record("a closed export must not report a print failure or replace its destination")
        } catch is CancellationError {
            // Closure takes precedence over the unsuccessful print result.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }

        #expect(try Data(contentsOf: destination) == prior)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == ["out.pdf"], "print and snapshot scratch files must be retired")
    }
}

import AppKit
import Foundation
@testable import MacDown2
import PDFKit
import Testing
import WebKit

/// Opt-in hosted experiment for AppKit's document-modal print API. It does not
/// change the production synchronous print path or claim a cancellation bound.
@MainActor
struct PDFModalPrintFeasibilityTests {
    private nonisolated static var enabled: Bool {
        #if PDF_MODAL_PROBE
            true
        #else
            false
        #endif
    }

    @Test(.enabled(if: enabled, "requires owned hosted PDF modal qualification"))
    func webKitPrintModalCompletesWithAnActiveMainRunLoop() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-pdf-modal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdfURL = directory.appendingPathComponent("modal.pdf")
        let info = PDFExportAdapter.printInfo(savingTo: pdfURL)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 800),
                                configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        let navigation = PDFNavigationDelegate()
        webView.navigationDelegate = navigation
        let sections = (1 ... 25).map { index in
            "<section><h2>Section \(index)</h2>" +
                String(repeating: "<p>Searchable section \(index) text.</p>", count: 25) + "</section>"
        }.joined()
        try await navigation.load("<!doctype html><html><body>\(sections)</body></html>",
                                  in: webView, timeout: .seconds(30))

        let operation = webView.printOperation(with: info)
        operation.printInfo = info
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.canSpawnSeparateThread = true
        let printView = try #require(operation.view)
        printView.frame = webView.bounds
        printView.layoutSubtreeIfNeeded()
        let completion = ModalPrintCompletion()
        let heartbeats = MainRunLoopHeartbeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            heartbeats.tick()
        }
        let began = DispatchTime.now().uptimeNanoseconds
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            completion.arm(continuation)
            operation.runModal(for: window, delegate: completion,
                               didRun: #selector(ModalPrintCompletion.didRun(_:success:contextInfo:)),
                               contextInfo: nil)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
        timer.invalidate()
        print("pdf-modal-print success=\(success) elapsed_ms=\(elapsed) " +
            "main_run_loop_heartbeats=\(heartbeats.count) callback_on_main=\(completion.callbackOnMain)")
        #expect(success)
        #expect(heartbeats.count > 0)
        let bytes = try Data(contentsOf: pdfURL)
        let pdf = try #require(PDFDocument(data: bytes))
        #expect(pdf.pageCount > 1)
        #expect(pdf.string?.contains("Section 1") == true)
        #expect(pdf.string?.contains("Section 25") == true)
    }
}

private final class ModalPrintCompletion: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var didRunOnMain = false

    func arm(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    @objc func didRun(_: NSPrintOperation, success: Bool, contextInfo _: UnsafeMutableRawPointer?) {
        let pending = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            didRunOnMain = Thread.isMainThread
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: success)
    }

    var callbackOnMain: Bool {
        lock.withLock { didRunOnMain }
    }
}

private final class MainRunLoopHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks = 0

    func tick() {
        lock.withLock { ticks += 1 }
    }

    var count: Int {
        lock.withLock { ticks }
    }
}

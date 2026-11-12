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
            onPhase: { phase in
                phases.append(phase)
                if phase == .printing {
                    heartbeat.start()
                }
                if phase == .validating {
                    heartbeat.stop()
                }
            },
            runPrint: { _ in
                Issue.record("The document-modal production path used the synchronous print fallback")
                return false
            }
        )
        #expect(phases == [.preparing, .loading, .printing, .validating, .publishing])
        #expect(!heartbeat.isEmpty)
        print("pdf-production-modal-print elapsed_ms=\(heartbeat.elapsedMilliseconds) " +
            "main_run_loop_heartbeats=\(heartbeat.count)")
        let pdf = try #require(PDFDocument(url: destination))
        #expect(pdf.pageCount > 1)
        #expect(pdf.string?.contains("Section 1") == true)
        #expect(pdf.string?.contains("Section 25") == true)
        try await verifyRevokedPrintPreservesExistingDestination(in: directory, window: window, sections: sections)
    }

    private func verifyRevokedPrintPreservesExistingDestination(
        in directory: URL, window: NSWindow, sections: String
    ) async throws {
        let cancelledDestination = directory.appendingPathComponent("cancelled.pdf")
        let previousBytes = Data("previous destination bytes".utf8)
        try previousBytes.write(to: cancelledDestination)
        let cancelledPrepared = try await ExportService.prepare(
            ExportRequest(text: "# Production modal PDF\n\n" + sections,
                          sourceGeneration: 2, theme: BundledThemes.light),
            target: .pdf(url: cancelledDestination)
        )
        let lease = ExportLifetimeLease()
        let revocation = ProductionPDFRevocation(lease: lease)
        var reachedPrint = false
        do {
            try await PDFExportAdapter.export(
                cancelledPrepared, to: cancelledDestination, lease: lease, modalWindow: window,
                onPhase: { phase in
                    if phase == .printing {
                        reachedPrint = true
                        DispatchQueue.main.async { revocation.revoke() }
                    }
                },
                runPrint: { _ in
                    Issue.record("The revoked modal export used the synchronous print fallback")
                    return false
                }
            )
            Issue.record("A print completed after lease revocation and replaced the destination")
        } catch is CancellationError {
            // A revoked lease wins after AppKit returns and before publication.
        }
        #expect(reachedPrint)
        #expect(revocation.didRevoke)
        #expect(try Data(contentsOf: cancelledDestination) == previousBytes)
        print("pdf-production-modal-revocation preserved_existing_destination=true")
    }
}

private final class ProductionPDFRevocation: @unchecked Sendable {
    private let lease: ExportLifetimeLease
    private let lock = NSLock()
    private var revoked = false

    init(lease: ExportLifetimeLease) {
        self.lease = lease
    }

    func revoke() {
        lease.revoke()
        lock.withLock { revoked = true }
    }

    var didRevoke: Bool {
        lock.withLock { revoked }
    }
}

private final class ProductionPDFHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks = 0
    private var active = false
    private var started: UInt64?
    private var stopped: UInt64?

    func start() {
        lock.withLock {
            started = DispatchTime.now().uptimeNanoseconds
            active = true
        }
    }

    func stop() {
        lock.withLock {
            active = false
            stopped = DispatchTime.now().uptimeNanoseconds
        }
    }

    func tick() {
        lock.withLock {
            if active {
                ticks += 1
            }
        }
    }

    var isEmpty: Bool {
        lock.withLock { ticks == 0 }
    }

    var count: Int {
        lock.withLock { ticks }
    }

    var elapsedMilliseconds: Double {
        lock.withLock {
            guard let started, let stopped, stopped >= started else { return -1 }
            return Double(stopped - started) / 1_000_000
        }
    }
}

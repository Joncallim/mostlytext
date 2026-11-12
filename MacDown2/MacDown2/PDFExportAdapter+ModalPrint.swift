import AppKit
import Foundation

enum PDFExportPhase: Equatable {
    case preparing
    case loading
    case printing
    case validating
    case publishing
}

@MainActor
extension PDFExportAdapter {
    static func runPrintOperation(
        _ operation: NSPrintOperation, in window: NSWindow?,
        fallback: @MainActor (NSPrintOperation) -> Bool
    ) async -> Bool {
        guard let window else { return fallback(operation) }
        // AppKit owns the active print interval. The document-modal API with
        // a separate print thread keeps the main run loop responsive; an
        // export cancelled during this interval refuses publication on return.
        operation.canSpawnSeparateThread = true
        operation.showsProgressPanel = false
        let completion = PDFModalPrintCompletion()
        let printed = await withCheckedContinuation { continuation in
            completion.arm(continuation)
            operation.runModal(for: window, delegate: completion,
                               didRun: #selector(PDFModalPrintCompletion.didRun(_:success:contextInfo:)),
                               contextInfo: nil)
        }
        withExtendedLifetime(completion) {}
        return printed
    }
}

/// The print callback is allowed to arrive off the main thread. Resume the
/// suspended export exactly once, then let its main-actor task validate output.
final class PDFModalPrintCompletion: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    func arm(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    @objc func didRun(_: NSPrintOperation, success: Bool, contextInfo _: UnsafeMutableRawPointer?) {
        let pending = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: success)
    }
}

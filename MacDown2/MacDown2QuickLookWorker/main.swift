import Darwin
import Foundation
import QuickLookBoundary
import QuickLookSource
import Security
#if QUICKLOOK_DERIVED_PROBE
    import Math
    import MathRendering
#endif

private let maximumOutputBytes = QuickLookSourceBudget.maximumHTMLBytes

private func hasRequiredSandbox() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let sandbox = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool
    let network = SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil)
    return sandbox == true && network == nil
}

private func writeAll(_ descriptor: Int32, bytes: Data) -> Bool {
    bytes.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return bytes.isEmpty }
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
}

private func sourceWorkerMain() -> Never {
    // The service also kills/reaps this exact child at three seconds. This
    // independent in-child guard prevents an orphaned blocked read if the
    // service itself disappears after spawning it.
    let watchdogReady = DispatchSemaphore(value: 0)
    let expires = ProcessInfo.processInfo.systemUptime + 3.5
    Thread.detachNewThread {
        watchdogReady.signal()
        let remaining = expires - ProcessInfo.processInfo.systemUptime
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
        Darwin._exit(124)
    }
    guard watchdogReady.wait(timeout: .now() + .milliseconds(200)) == .success else {
        Darwin._exit(125)
    }
    guard hasRequiredSandbox(), CommandLine.arguments.count == 2,
          lseek(3, 0, SEEK_SET) == 0,
          let html = try? QuickLookSourceFallback.replyHTML(forOpenDescriptor: 3),
          html.count <= maximumOutputBytes,
          writeAll(4, bytes: html)
    else { Darwin._exit(1) }
    Darwin._exit(0)
}

#if QUICKLOOK_DERIVED_PROBE
    /// Hosted-only feasibility probe, compiled out of the distributable worker.
    /// It uses this exact XPC executable and its sandbox-only entitlement.
    private func probeMathInSandbox() -> Never {
        guard hasRequiredSandbox() else { Darwin._exit(130) }
        let started = ProcessInfo.processInfo.systemUptime
        let context = ExportMathRenderContext(
            foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1,
            pixelScale: MathImageRenderer.standardScale
        )
        let image = MainActor.assumeIsolated {
            try? MathImageRenderer.render(
                span: MathSpan(range: 0 ..< 3, style: .inline, latex: "x^2"),
                context: context
            )
        }
        guard let image, !image.pngData.isEmpty else { Darwin._exit(131) }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print("QUICKLOOK_SANDBOX_MATH_PROBE pngBytes=\(image.pngData.count) elapsed=\(elapsed)")
        fflush(stdout)
        Darwin._exit(0)
    }

    if CommandLine.arguments == [CommandLine.arguments[0], "--probe-math"] {
        probeMathInSandbox()
    }
#endif

if CommandLine.arguments.count > 1 {
    guard CommandLine.arguments == [CommandLine.arguments[0], "--source-worker"] else { Darwin._exit(126) }
    sourceWorkerMain()
}

private final class WorkAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func claim() -> Bool {
        lock.withLock {
            guard count < 2 else { return false }
            count += 1
            return true
        }
    }

    func release() {
        lock.withLock { count -= 1 }
    }
}

private let admission = WorkAdmission()

private final class SourceReply: @unchecked Sendable {
    private let send: (NSData?, NSNumber) -> Void

    init(_ send: @escaping (NSData?, NSNumber) -> Void) {
        self.send = send
    }

    func finish(_ data: Data?, status: QuickLookWorkerStatus) {
        send(data as NSData?, NSNumber(value: status.rawValue))
    }
}

private final class SourceHandler: NSObject, QuickLookWorkerProtocol {
    func renderSource(_ selectedFile: FileHandle,
                      withReply reply: @escaping (NSData?, NSNumber) -> Void) {
        guard hasRequiredSandbox(), admission.claim() else {
            reply(nil, NSNumber(value: QuickLookWorkerStatus.refused.rawValue))
            return
        }
        let retained = selectedFile
        let completion = SourceReply(reply)
        Thread.detachNewThread {
            defer { admission.release() }
            let result = SourceProcess.run(selectedDescriptor: retained.fileDescriptor)
            completion.finish(result.data, status: result.status)
        }
    }
}

private final class BootstrapListener: NSObject, NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: QuickLookWorkerProtocol.self)
        connection.exportedObject = SourceHandler()
        connection.resume()
        return true
    }
}

private let delegate = BootstrapListener()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

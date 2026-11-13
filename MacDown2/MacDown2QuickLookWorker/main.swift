import Darwin
import Foundation
import QuickLookBoundary
import QuickLookSource
import Security
#if QUICKLOOK_DERIVED_PROBE
    import Contributions
    import ExportService
    import MarkdownEngine
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

#if QUICKLOOK_DERIVED_MATH
    @MainActor
    private final class DerivedReplyState {
        var completed = false
        var reply: Data?
    }
#endif

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
          let source = try? QuickLookSourceFallback.selectedSource(forOpenDescriptor: 3)
    else { Darwin._exit(1) }
    let fallback = QuickLookSourceFallback.replyHTML(
        forSource: source, contributions: [], sourceGeneration: 0
    )
    guard fallback.count <= maximumOutputBytes,
          writeAll(4, bytes: fallback),
          writeAll(6, bytes: Data([0x46]))
    else { Darwin._exit(1) }
    // The source fallback and its marker are immutable before slower work.
    #if QUICKLOOK_DERIVED_MATH
        if source.contains("$") {
            guard Thread.isMainThread else { Darwin._exit(1) }
            let state = MainActor.assumeIsolated { DerivedReplyState() }
            Task { @MainActor in
                state.reply = await DerivedMathReply.render(source)
                state.completed = true
            }
            let publishDeadline = expires - 0.75
            while ProcessInfo.processInfo.systemUptime < publishDeadline,
                  !MainActor.assumeIsolated({ state.completed }) {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            let derived = MainActor.assumeIsolated { state.completed ? state.reply : nil }
            if let derived, derived.count <= maximumOutputBytes {
                guard writeAll(5, bytes: derived),
                      writeAll(6, bytes: Data([0x44]))
                else { Darwin._exit(1) }
            }
        }
    #endif
    Darwin._exit(0)
}

#if QUICKLOOK_DERIVED_PROBE
    @MainActor
    private final class MathProbeState {
        var completed = false
        var outcome = "not started"
    }

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

    // Check the existing validated analysis, contributor and passive HTML
    // composition inside the same hosted worker. This remains a fixed probe
    // and does not consume the selected document or publish a Finder reply.
    if CommandLine.arguments == [CommandLine.arguments[0], "--probe-shared-math"] {
        guard hasRequiredSandbox() else { Darwin._exit(132) }
        let state = MainActor.assumeIsolated { MathProbeState() }
        let started = ProcessInfo.processInfo.systemUptime
        Task { @MainActor in
            do {
                let source = "Equation $x^2$ and source."
                let document = try await ParseEngine().parse(source, revision: 1)
                let context = ExportMathRenderContext(
                    foregroundRed: 0.1, foregroundGreen: 0.1, foregroundBlue: 0.1,
                    pixelScale: MathImageRenderer.standardScale
                )
                let contributor = SharedMathContribution(context: context) { body, style, context in
                    try await MainActor.run {
                        try MathImageRenderer.render(body: body, style: style, context: context)
                    }
                }
                let results = try await contributor.run(document: document, sourceText: source, sourceGeneration: 1)
                guard results.count == 1, let content = results[0].content,
                      case let .html(fragment) = content.representation,
                      fragment.contains("data:image/png;base64,")
                else { throw NSError(domain: "QuickLookMathProbe", code: 1) }
                let placement: ExportDerivedPlacement = content.placement == .inline ? .inline : .block
                let item = ExportDerivedContribution(
                    sourceRange: content.sourceRange, placement: placement,
                    html: fragment, sourceGeneration: results[0].sourceGeneration
                )
                let composed = ExportService.renderPassiveMarkdownFragment(
                    source, contributions: [item], sourceGeneration: 1
                )
                guard composed.contains("data:image/png;base64,"), !composed.contains("$x^2$")
                else { throw NSError(domain: "QuickLookMathProbe", code: 2) }
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                state.outcome = "htmlBytes=\(composed.utf8.count) elapsed=\(elapsed)"
            } catch {
                state.outcome = "failure=\(error)"
            }
            state.completed = true
        }
        let deadline = Date().addingTimeInterval(3.5)
        while Date() < deadline, !MainActor.assumeIsolated({ state.completed }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let outcome = MainActor.assumeIsolated { state.outcome }
        print("QUICKLOOK_SHARED_MATH_PROBE \(outcome)")
        fflush(stdout)
        Darwin._exit(outcome.hasPrefix("htmlBytes=") ? 0 : 133)
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

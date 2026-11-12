import Foundation
import QuickLookSource

/// The extension waits only for the bounded, sandboxed source service. The
/// service owns the child deadline and reaps that exact process on timeout.
enum QuickLookWorkerClient {
    private static let serviceName = "app.mostlytext.MostlyText.QuickLook.Worker"
    private static let maximumReplyBytes = QuickLookSourceFallback.maximumSourceBytes * 6 + 4096

    static func renderSource(_ selected: FileHandle) async -> Data? {
        let result = OneShotSourceReply()
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: QuickLookWorkerProtocol.self)
        connection.interruptionHandler = { result.finish(nil) }
        connection.invalidationHandler = { result.finish(nil) }
        connection.resume()
        guard let remote = connection.remoteObjectProxyWithErrorHandler({ _ in result.finish(nil) })
            as? QuickLookWorkerProtocol
        else {
            connection.invalidate()
            return nil
        }
        remote.renderSource(selected) { bytes, status in
            guard status.intValue == QuickLookWorkerStatus.complete.rawValue,
                  let bytes, bytes.length <= maximumReplyBytes
            else { result.finish(nil); return }
            result.finish(bytes as Data)
        }
        let deadline = Task.detached {
            try? await Task.sleep(for: .seconds(4))
            result.finish(nil)
        }
        let html = await withTaskCancellationHandler {
            await result.value()
        } onCancel: {
            result.finish(nil)
        }
        deadline.cancel()
        connection.invalidate()
        return Task.isCancelled ? nil : html
    }
}

private final class OneShotSourceReply: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var completedValue: Data?
    private var continuation: CheckedContinuation<Data?, Never>?

    func finish(_ data: Data?) {
        let pending = lock.withLock { () -> CheckedContinuation<Data?, Never>? in
            guard !finished else { return nil }
            finished = true
            completedValue = data
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: data)
    }

    func value() async -> Data? {
        await withCheckedContinuation { pending in
            let ready = lock.withLock { () -> (Bool, Data?) in
                if finished {
                    return (true, completedValue)
                }
                continuation = pending
                return (false, nil)
            }
            if ready.0 {
                pending.resume(returning: ready.1)
            }
        }
    }
}

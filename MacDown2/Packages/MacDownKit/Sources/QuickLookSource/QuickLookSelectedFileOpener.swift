import Foundation

/// Keeps a slow system-selected regular-file open off the Quick Look reply
/// executor. A timed-out open may remain blocked in the kernel, so the two
/// admitted worker slots stay occupied until their actual syscalls return.
public enum QuickLookSelectedFileOpener {
    private static let admission = Admission()

    public static func open(_ url: URL) async throws -> FileHandle {
        try await open(url, timeout: .seconds(1)) {
            try QuickLookSourceFallback.openSelectedFile(url)
        }
    }

    static func open(
        _: URL, timeout: Duration,
        operation: @escaping @Sendable () throws -> FileHandle
    ) async throws -> FileHandle {
        guard admission.claim() else { throw QuickLookSourceError.openBusy }
        let reply = OneShotOpen()
        let deadline = Task.detached {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            reply.finish(.failure(.openTimedOut))
        }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                reply.arm(continuation)
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { admission.release() }
                    do {
                        let selected = try operation()
                        if !reply.finish(.success(selected)) {
                            try? selected.close()
                        }
                    } catch let error as QuickLookSourceError {
                        reply.finish(.failure(error))
                    } catch {
                        reply.finish(.failure(.openFailed))
                    }
                }
            }
        } onCancel: {
            reply.finish(.failure(.openFailed))
        }
        deadline.cancel()
        do {
            try Task.checkCancellation()
        } catch {
            if case let .success(selected) = result {
                try? selected.close()
            }
            throw error
        }
        return try result.get()
    }
}

private final class Admission: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0

    func claim() -> Bool {
        lock.withLock {
            guard active < 2 else { return false }
            active += 1
            return true
        }
    }

    func release() {
        lock.withLock { active -= 1 }
    }
}

private final class OneShotOpen: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var value: Result<FileHandle, QuickLookSourceError>?
    private var continuation: CheckedContinuation<Result<FileHandle, QuickLookSourceError>, Never>?

    func arm(_ continuation: CheckedContinuation<Result<FileHandle, QuickLookSourceError>, Never>) {
        let ready = lock.withLock { () -> Result<FileHandle, QuickLookSourceError>? in
            if completed {
                return value
            }
            self.continuation = continuation
            return nil
        }
        if let ready {
            continuation.resume(returning: ready)
        }
    }

    @discardableResult
    func finish(_ result: Result<FileHandle, QuickLookSourceError>) -> Bool {
        let pending = lock.withLock { () -> (
            Bool,
            CheckedContinuation<Result<FileHandle, QuickLookSourceError>, Never>?
        ) in
            guard !completed else { return (false, nil) }
            completed = true
            value = result
            defer { continuation = nil }
            return (true, continuation)
        }
        pending.1?.resume(returning: result)
        return pending.0
    }
}

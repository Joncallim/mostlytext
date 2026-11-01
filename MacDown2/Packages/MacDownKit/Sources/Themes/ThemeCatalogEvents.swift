import CoreServices
import Foundation

public enum ThemeCatalogChange: Sendable, Equatable {
    case changed
    case rootChanged
}

/// The C stream is confined to setup and its serial shutdown queue. The lock
/// transfers its single shutdown ownership and protects completion waiters.
final class ThemeCatalogEvents: @unchecked Sendable {
    let events: AsyncStream<ThemeCatalogChange>
    private let queue = DispatchQueue(label: "app.mostlytext.theme-events", qos: .utility)
    private let lock = NSLock()
    private var state: StreamState?
    private var stopped = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(path: String) throws {
        let pair = AsyncStream<ThemeCatalogChange>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pair.stream
        let receiver = Receiver(continuation: pair.continuation)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(receiver).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                return UnsafeRawPointer(Unmanaged<Receiver>.fromOpaque(pointer).retain().toOpaque())
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<Receiver>.fromOpaque(pointer).release()
            }, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            nil, { _, info, count, _, flags, _ in
                guard let info else { return }
                let receiver = Unmanaged<Receiver>.fromOpaque(info).takeUnretainedValue()
                let rootChanged = (0 ..< min(count, 1024)).contains {
                    flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                }
                receiver.continuation.yield(rootChanged ? .rootChanged : .changed)
            }, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags
        ) else { throw ThemeStorageError.unavailable(EIO) }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            pair.continuation.finish()
            throw ThemeStorageError.unavailable(EIO)
        }
        state = StreamState(stream: stream, receiver: receiver)
        pair.continuation.onTermination = { [weak self] _ in self?.cancel() }
    }

    deinit {
        // Never capture self from deinit. The queued state owns the C stream
        // and callback receiver until the real shutdown finishes.
        let state = state
        let completions = waiters
        guard state != nil || !completions.isEmpty else { return }
        queue.async {
            state?.stop()
            for completion in completions {
                completion.resume()
            }
        }
    }

    func cancel() {
        beginStop(waiter: nil)
    }

    func cancelAndWait() async {
        await withCheckedContinuation { beginStop(waiter: $0) }
    }

    private func beginStop(waiter: CheckedContinuation<Void, Never>?) {
        lock.lock()
        if stopped {
            lock.unlock()
            waiter?.resume()
            return
        }
        if let waiter {
            waiters.append(waiter)
        }
        let closing = state
        state = nil
        lock.unlock()
        guard let closing else { return }
        queue.async {
            closing.stop()
            self.completeStop()
        }
    }

    private func completeStop() {
        lock.lock()
        stopped = true
        let completions = waiters
        waiters.removeAll()
        lock.unlock()
        for completion in completions {
            completion.resume()
        }
    }

    private final class Receiver: Sendable {
        let continuation: AsyncStream<ThemeCatalogChange>.Continuation
        init(continuation: AsyncStream<ThemeCatalogChange>.Continuation) {
            self.continuation = continuation
        }
    }

    /// No reference to the catalog, window or observer owner is captured by
    /// the framework. Stop guarantees callbacks end before context release.
    private final class StreamState: @unchecked Sendable {
        let stream: FSEventStreamRef
        let receiver: Receiver
        init(stream: FSEventStreamRef, receiver: Receiver) {
            self.stream = stream
            self.receiver = receiver
        }

        func stop() {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            receiver.continuation.finish()
        }
    }
}

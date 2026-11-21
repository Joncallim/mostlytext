import CoreServices
import Foundation

/// Recursive changes to one selected workspace. Paths are deliberately not
/// surfaced: every event requests a fresh, bounded index walk, and a root
/// move invalidates actions before another path can be admitted.
public enum WorkspaceFileChange: Sendable, Equatable {
    case changed
    case rootChanged
}

public protocol WorkspaceEventSource: Sendable {
    var events: AsyncStream<WorkspaceFileChange> { get }
    func cancel()
}

/// One FSEvents stream per open workspace, regardless of directory count.
/// The stream's C lifetime is confined to its serial queue; cancellation
/// retains its callback receiver until that queue has stopped the stream.
public final class WorkspaceFileEvents: @unchecked Sendable, WorkspaceEventSource {
    public let events: AsyncStream<WorkspaceFileChange>
    private let queue = DispatchQueue(label: "app.mostlytext.workspace-events", qos: .utility)
    private let lock = NSLock()
    private var state: StreamState?
    private var stopped = false

    public init(path: String) throws {
        let pair = AsyncStream<WorkspaceFileChange>.makeStream(bufferingPolicy: .bufferingNewest(1))
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
        ) else { throw CocoaError(.fileReadUnknown) }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            pair.continuation.finish()
            throw CocoaError(.fileReadUnknown)
        }
        state = StreamState(stream: stream, receiver: receiver)
        pair.continuation.onTermination = { [weak self] _ in self?.cancel() }
    }

    deinit {
        let state = state
        queue.async { state?.stop() }
    }

    public func cancel() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let closing = state
        state = nil
        lock.unlock()
        queue.async { closing?.stop() }
    }

    private final class Receiver: Sendable {
        let continuation: AsyncStream<WorkspaceFileChange>.Continuation
        init(continuation: AsyncStream<WorkspaceFileChange>.Continuation) {
            self.continuation = continuation
        }
    }

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

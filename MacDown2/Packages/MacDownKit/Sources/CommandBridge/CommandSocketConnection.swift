import Darwin
import Foundation

public enum CommandSocketError: Error, Sendable, Equatable {
    case closed
    case timedOut
    case cancelled
    case unavailable(Int32)
}

/// A single off-main serialized owner takes the descriptor; do not retain or
/// close another copy of it. This type intentionally has no Sendable conformance.
public final class CommandSocketConnection {
    private var descriptor: Int32
    private var decoder = CommandFrameDecoder()
    private var unread = Data()

    public init(adopting descriptor: Int32) throws {
        self.descriptor = descriptor
        do {
            try CommandSocketPeer.requireCurrentUser(descriptor)
            let status = fcntl(descriptor, F_GETFL)
            let flags = fcntl(descriptor, F_GETFD)
            guard status >= 0, flags >= 0,
                  fcntl(descriptor, F_SETFL, status | O_NONBLOCK) == 0,
                  fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) == 0 else {
                throw CommandSocketError.unavailable(errno)
            }
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    public func close() {
        if descriptor >= 0 {
            Darwin.close(descriptor); descriptor = -1
        }
        unread = Data()
        decoder.cancel()
    }

    /// nil is clean EOF; Data() is an actual empty frame. Input and handshake
    /// callers must pass a deadline. nil is reserved for document-lifetime wait.
    public func readFrame(until deadline: ContinuousClock.Instant?,
                          isCancelled: () -> Bool = { false }) throws -> Data? {
        do {
            while true {
                try check(deadline: deadline, isCancelled: isCancelled)
                if !unread.isEmpty {
                    let result = try decoder.consume(unread)
                    unread = unread.dropFirst(result.consumedBytes)
                    if let frame = result.frame {
                        try check(deadline: deadline, isCancelled: isCancelled)
                        return frame
                    }
                }
                try ready(for: Int16(POLLIN), deadline: deadline, isCancelled: isCancelled)
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = recv(descriptor, &bytes, bytes.count, 0)
                if count > 0 {
                    unread = Data(bytes.prefix(count))
                } else if count == 0 {
                    try decoder.finish()
                    close()
                    return nil
                } else if errno != EINTR, errno != EAGAIN, errno != EWOULDBLOCK {
                    throw CommandSocketError.unavailable(errno)
                }
            }
        } catch {
            close()
            throw error
        }
    }

    public func writeFrame(_ payload: Data, until deadline: ContinuousClock.Instant,
                           isCancelled: () -> Bool = { false }) throws {
        do {
            try check(deadline: deadline, isCancelled: isCancelled)
            let frame = try CommandFrameDecoder.encode(payload)
            try frame.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { throw CommandProtocolError.invalidState }
                var offset = 0
                while offset < bytes.count {
                    try ready(for: Int16(POLLOUT), deadline: deadline, isCancelled: isCancelled)
                    // Per-send protection also works if the peer closed before
                    // adoption; SO_NOSIGPIPE can fail with EINVAL in that race.
                    let count = send(descriptor, base.advanced(by: offset), bytes.count - offset, MSG_NOSIGNAL)
                    if count > 0 {
                        offset += count
                    } else if count == 0 {
                        throw CommandSocketError.closed
                    } else if errno != EINTR, errno != EAGAIN, errno != EWOULDBLOCK {
                        throw CommandSocketError.unavailable(errno)
                    }
                }
            }
        } catch {
            close()
            throw error
        }
    }

    private func check(deadline: ContinuousClock.Instant?, isCancelled: () -> Bool) throws {
        guard descriptor >= 0 else { throw CommandSocketError.closed }
        if isCancelled() {
            throw CommandSocketError.cancelled
        }
        if let deadline, ContinuousClock.now >= deadline {
            throw CommandSocketError.timedOut
        }
    }

    private func ready(for event: Int16, deadline: ContinuousClock.Instant?, isCancelled: () -> Bool) throws {
        try CommandSocketPolling.wait(descriptor, event: event, deadline: deadline, cancelled: isCancelled)
    }
}

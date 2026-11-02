import CommandBridge
import Darwin
import Foundation

public enum CommandLineInputFailure: Error, Sendable, Equatable {
    case unavailable(Int32)
    case tooLarge
    case invalidUTF8
    case timedOut
    case cancelled
}

public enum CommandLineStdin {
    /// One caller owns the descriptor for this operation. Restore its flags
    /// on every exit; stdin stays open and its exact bytes are retained.
    public static func read(descriptor: Int32, until deadline: ContinuousClock.Instant,
                            isCancelled: () -> Bool = { false }) throws -> Data {
        let original = fcntl(descriptor, F_GETFL)
        guard original >= 0, fcntl(descriptor, F_SETFL, original | O_NONBLOCK) == 0 else {
            throw CommandLineInputFailure.unavailable(errno)
        }
        let result = Result { try receive(descriptor: descriptor, until: deadline, isCancelled: isCancelled) }
        guard fcntl(descriptor, F_SETFL, original) == 0 else { throw CommandLineInputFailure.unavailable(errno) }
        return try result.get()
    }

    private static func receive(descriptor: Int32, until deadline: ContinuousClock.Instant,
                                isCancelled: () -> Bool) throws -> Data {
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            try wait(descriptor, until: deadline, isCancelled: isCancelled)
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            let failure = errno
            if count == 0 {
                try check(deadline, isCancelled: isCancelled)
                guard String(data: bytes, encoding: .utf8) != nil else { throw CommandLineInputFailure.invalidUTF8 }
                try check(deadline, isCancelled: isCancelled)
                return bytes
            }
            if count < 0 {
                if failure == EINTR || failure == EAGAIN || failure == EWOULDBLOCK {
                    continue
                }
                throw CommandLineInputFailure.unavailable(failure)
            }
            guard count <= CommandProtocol.maximumStdinBytes - bytes.count
            else { throw CommandLineInputFailure.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func check(_ deadline: ContinuousClock.Instant, isCancelled: () -> Bool) throws {
        if isCancelled() {
            throw CommandLineInputFailure.cancelled
        }
        guard ContinuousClock.now < deadline else { throw CommandLineInputFailure.timedOut }
    }

    private static func wait(_ descriptor: Int32, until deadline: ContinuousClock.Instant,
                             isCancelled: () -> Bool) throws {
        while true {
            try check(deadline, isCancelled: isCancelled)
            var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&item, 1, 50)
            if ready < 0 {
                if errno == EINTR {
                    continue
                }
                throw CommandLineInputFailure.unavailable(errno)
            }
            try check(deadline, isCancelled: isCancelled)
            if ready == 0 {
                continue
            }
            guard item.revents & Int16(POLLNVAL) == 0 else { throw CommandLineInputFailure.unavailable(EBADF) }
            return
        }
    }
}

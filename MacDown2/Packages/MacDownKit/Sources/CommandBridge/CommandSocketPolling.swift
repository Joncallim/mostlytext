import Darwin
import Foundation

enum CommandSocketPolling {
    static func check(_ descriptor: Int32, deadline: ContinuousClock.Instant?, cancelled: () -> Bool) throws {
        guard descriptor >= 0 else { throw CommandSocketError.closed }
        if cancelled() {
            throw CommandSocketError.cancelled
        }
        if let deadline, ContinuousClock.now >= deadline {
            throw CommandSocketError.timedOut
        }
    }

    static func wait(_ descriptor: Int32, event: Int16, deadline: ContinuousClock.Instant?,
                     cancelled: () -> Bool) throws {
        while true {
            try check(descriptor, deadline: deadline, cancelled: cancelled)
            var item = pollfd(fd: descriptor, events: event, revents: 0)
            let count = poll(&item, 1, milliseconds(until: deadline))
            if count > 0 {
                try check(descriptor, deadline: deadline, cancelled: cancelled)
                guard item.revents & Int16(POLLNVAL) == 0 else { throw CommandSocketError.closed }
                if item.revents & (event | Int16(POLLHUP | POLLERR)) != 0 {
                    return
                }
            } else if count < 0, errno != EINTR {
                throw CommandSocketError.unavailable(errno)
            }
        }
    }

    private static func milliseconds(until deadline: ContinuousClock.Instant?) -> Int32 {
        guard let deadline else { return 50 }
        let remaining = ContinuousClock.now.duration(to: deadline)
        if remaining <= .zero {
            return 0
        }
        if remaining >= .milliseconds(50) {
            return 50
        }
        let perMillisecond: Int64 = 1_000_000_000_000_000
        return Int32((remaining.components.attoseconds + perMillisecond - 1) / perMillisecond)
    }

    static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CommandSocketError.unavailable(errno) }
        let flags = fcntl(descriptor, F_GETFL)
        let fdFlags = fcntl(descriptor, F_GETFD)
        guard flags >= 0, fdFlags >= 0,
              fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, fdFlags | FD_CLOEXEC) == 0 else {
            let error = errno
            Darwin.close(descriptor)
            throw CommandSocketError.unavailable(error)
        }
        return descriptor
    }

    static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString).map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw CommandEndpointError.invalidLocation
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func connect(_ descriptor: Int32, path: String, deadline: ContinuousClock.Instant,
                        cancelled: () -> Bool) throws {
        try check(descriptor, deadline: deadline, cancelled: cancelled)
        let result = try withAddress(path) { Darwin.connect(descriptor, $0, $1) }
        if result != 0 {
            guard errno == EINPROGRESS || errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK else {
                throw CommandSocketError.unavailable(errno)
            }
            try wait(descriptor, event: Int16(POLLOUT), deadline: deadline, cancelled: cancelled)
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout.size(ofValue: error))
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0 else {
                throw CommandSocketError.unavailable(errno)
            }
            guard error == 0 else { throw CommandSocketError.unavailable(error) }
        }
        try check(descriptor, deadline: deadline, cancelled: cancelled)
    }
}

import Darwin
import Foundation

/// One serialized off-main owner. Construction activates only this private
/// socket, never an application, document or request worker.
public final class CommandEndpointListener {
    public let location: CommandEndpointLocation
    public let instanceID = UUID()
    private let lease: CommandEndpointLease
    private let namespace: CommandEndpointNamespace
    private var descriptor: Int32 = -1
    private var ownedIdentity: CommandSocketIdentity?

    public init(location: CommandEndpointLocation, until deadline: ContinuousClock.Instant,
                isCancelled: @Sendable () -> Bool = { false }) throws {
        self.location = location
        lease = try CommandEndpointLease(location: location)
        namespace = try CommandEndpointNamespace(location)
        do {
            descriptor = try CommandSocketPolling.makeSocket()
            try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
            if let existing = try namespace.socketIdentity() {
                try requireRefusedEndpoint(until: deadline, isCancelled: isCancelled)
                try lease.verifyOwnership()
                try namespace.retireSocket(expected: existing)
            }
            try lease.verifyOwnership()
            try namespace.verify()
            try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
            guard try CommandSocketPolling.withAddress(location.socketPath, {
                Darwin.bind(descriptor, $0, $1)
            }) == 0 else { throw CommandSocketError.unavailable(errno) }
            guard let identity = try namespace.socketIdentity(requirePrivateMode: false) else {
                throw CommandEndpointError.identityChanged
            }
            ownedIdentity = identity
            try namespace.secureSocket(expected: identity)
            guard Darwin.listen(descriptor, 8) == 0 else { throw CommandSocketError.unavailable(errno) }
            try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
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
        if let ownedIdentity {
            if (try? lease.verifyOwnership()) != nil {
                try? namespace.retireSocket(expected: ownedIdentity)
            }
            self.ownedIdentity = nil
        }
        lease.release()
    }

    public func accept(until deadline: ContinuousClock.Instant,
                       isCancelled: @Sendable () -> Bool = { false }) throws -> sending CommandSocketConnection {
        while true {
            try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
            try lease.verifyOwnership()
            guard try namespace.socketIdentity() == ownedIdentity else { throw CommandEndpointError.identityChanged }
            try CommandSocketPolling.wait(descriptor, event: Int16(POLLIN), deadline: deadline, cancelled: isCancelled)
            let accepted = Darwin.accept(descriptor, nil, nil)
            if accepted < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                    continue
                }
                throw CommandSocketError.unavailable(errno)
            }
            // The constructor takes ownership even when its peer/flag checks fail.
            let connection = try CommandSocketConnection(adopting: accepted)
            do {
                try lease.verifyOwnership()
                try namespace.verify()
                guard try namespace.socketIdentity() == ownedIdentity else {
                    throw CommandEndpointError.identityChanged
                }
                try connection.writeFrame(CommandInstanceHello.encode(instanceID: instanceID), until: deadline,
                                          isCancelled: isCancelled)
                return connection
            } catch {
                connection.close()
                throw error
            }
        }
    }

    private func requireRefusedEndpoint(until deadline: ContinuousClock.Instant,
                                        isCancelled: @Sendable () -> Bool) throws {
        let probe = try CommandSocketPolling.makeSocket()
        defer { Darwin.close(probe) }
        do {
            try CommandSocketPolling.connect(
                probe,
                path: location.socketPath,
                deadline: deadline,
                cancelled: isCancelled
            )
        } catch CommandSocketError.unavailable(ECONNREFUSED) {
            return
        }
        // Even an incompatible or nonresponding peer may be a live instance.
        throw CommandEndpointError.instanceBusy
    }
}

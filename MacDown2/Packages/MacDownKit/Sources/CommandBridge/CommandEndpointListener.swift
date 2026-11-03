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
    private var stagedLeaf: String?

    public convenience init(location: CommandEndpointLocation, until deadline: ContinuousClock.Instant,
                            isCancelled: @Sendable () -> Bool = { false }) throws {
        try self.init(location: location, until: deadline, isCancelled: isCancelled, afterBind: nil)
    }

    init(location: CommandEndpointLocation, until deadline: ContinuousClock.Instant,
         isCancelled: @Sendable () -> Bool = { false }, afterBind: (@Sendable () throws -> Void)?) throws {
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
            let (leaf, identity) = try namespace.bindStagedSocket(descriptor, until: deadline, isCancelled: isCancelled)
            stagedLeaf = leaf
            ownedIdentity = identity
            try afterBind?()
            try namespace.secureSocket(expected: identity, leaf: leaf)
            guard Darwin.listen(descriptor, 8) == 0 else { throw CommandSocketError.unavailable(errno) }
            try lease.verifyOwnership()
            try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
            try namespace.publishSocket(from: leaf, expected: identity)
            stagedLeaf = nil
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
                if let stagedLeaf {
                    try? namespace.retireSocket(expected: ownedIdentity, leaf: stagedLeaf)
                }
                // Publication may have succeeded before its final verification
                // threw. Exact identity checks protect any replacement.
                try? namespace.retireSocket(expected: ownedIdentity)
            }
            self.ownedIdentity = nil
            stagedLeaf = nil
        }
        lease.release()
    }

    public func accept(until deadline: ContinuousClock.Instant,
                       isCancelled: @Sendable () -> Bool = { false }) throws -> sending CommandSocketConnection {
        try accept(until: deadline, helloTimeout: nil, isCancelled: isCancelled)
    }

    /// The application polls idle admission separately from an accepted peer's
    /// greeting. Public callers retain their original single-deadline contract.
    func accept(until deadline: ContinuousClock.Instant, helloTimeout: Duration?,
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
            let helloDeadline = helloTimeout.map { ContinuousClock.now.advanced(by: $0) } ?? deadline
            // The constructor takes ownership even when its peer/flag checks fail.
            let connection = try CommandSocketConnection(adopting: accepted)
            do {
                try lease.verifyOwnership()
                try namespace.verify()
                guard try namespace.socketIdentity() == ownedIdentity else {
                    throw CommandEndpointError.identityChanged
                }
                try connection.writeFrame(CommandInstanceHello.encode(instanceID: instanceID), until: helloDeadline,
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

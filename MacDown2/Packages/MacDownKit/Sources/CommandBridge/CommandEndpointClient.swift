import Darwin
import Foundation

/// A connected stream and its hello-bound lifetime. The owner must carry this
/// instance UUID into any deliberate reconnect; the library never retries.
public struct CommandConnectedEndpoint {
    public let connection: CommandSocketConnection
    public let instanceID: UUID
}

public enum CommandEndpointClient {
    public static func connect(
        to location: CommandEndpointLocation,
        expecting expectedInstance: UUID? = nil,
        until deadline: ContinuousClock.Instant,
        isCancelled: () -> Bool = { false }
    ) throws -> CommandConnectedEndpoint {
        var descriptor = try CommandSocketPolling.makeSocket()
        defer {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
        }
        try CommandSocketPolling.check(descriptor, deadline: deadline, cancelled: isCancelled)
        let namespace = try CommandEndpointNamespace(location)
        guard let identity = try namespace.socketIdentity() else {
            throw CommandSocketError.unavailable(ENOENT)
        }
        try CommandSocketPolling.connect(descriptor, path: location.socketPath,
                                         deadline: deadline, cancelled: isCancelled)
        try namespace.verify()
        guard try namespace.socketIdentity() == identity else { throw CommandEndpointError.identityChanged }
        let adopted = descriptor
        descriptor = -1
        let connection = try CommandSocketConnection(adopting: adopted)
        do {
            guard let hello = try connection.readFrame(until: deadline, isCancelled: isCancelled) else {
                throw CommandProtocolError.invalidResponse
            }
            let instance = try CommandInstanceHello.decode(hello)
            guard expectedInstance == nil || expectedInstance == instance else {
                throw CommandEndpointError.instanceChanged
            }
            return CommandConnectedEndpoint(connection: connection, instanceID: instance)
        } catch {
            connection.close()
            throw error
        }
    }
}

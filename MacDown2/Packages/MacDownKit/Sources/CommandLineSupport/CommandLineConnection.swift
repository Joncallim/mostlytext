import CommandBridge
import Darwin
import Foundation

public enum CommandLineConnection {
    /// Before any request bytes, definite absence permits one verified launch
    /// and bounded startup polling. This never retries an accepted exchange.
    public static func connect(application: EmbeddedCommandApplication,
                               until deadline: ContinuousClock.Instant,
                               isCancelled: @escaping @Sendable () -> Bool = { false }) async throws
        -> sending CommandConnectedEndpoint {
        let location = try CommandEndpointLocation.forCurrentUser(productIdentity: application.bundleIdentifier)
        return try await connect(to: location, until: deadline, isCancelled: isCancelled) {
            try await application.launch(until: deadline, isCancelled: isCancelled)
        }
    }

    static func connect(to location: CommandEndpointLocation, until deadline: ContinuousClock.Instant,
                        isCancelled: @escaping @Sendable () -> Bool = { false },
                        launch: @escaping @Sendable () async throws -> Void) async throws
        -> sending CommandConnectedEndpoint {
        do {
            return try CommandEndpointClient.connect(to: location, until: deadline, isCancelled: isCancelled)
        } catch {
            guard isAbsent(error) else { throw error }
        }
        if isCancelled() {
            throw CommandSocketError.cancelled
        }
        try await launch()
        while true {
            if isCancelled() {
                throw CommandSocketError.cancelled
            }
            guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
            do {
                return try CommandEndpointClient.connect(to: location, until: deadline, isCancelled: isCancelled)
            } catch {
                guard isAbsent(error) else { throw error }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    static func isAbsent(_ error: any Error) -> Bool {
        switch error {
        case let CommandEndpointError.unavailable(code), let CommandSocketError.unavailable(code):
            code == ENOENT || code == ECONNREFUSED
        default: false
        }
    }
}

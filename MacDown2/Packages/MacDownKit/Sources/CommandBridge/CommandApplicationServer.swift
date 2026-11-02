import Darwin
import Foundation
import Synchronization

/// Bounded dedicated-thread transport; no blocking socket call uses MainActor
/// or the Swift cooperative executor. Stop never closes a worker-owned socket.
public final class CommandApplicationServer: Sendable {
    private struct Counts { var stopped = false; var connections = 0; var inputs = 0; var bytes = 0 }
    private let counts = Mutex(Counts())
    private let location: CommandEndpointLocation
    private let receiver: CommandApplicationReceiver
    private let failure = Mutex<(any Error)?>(nil)
    public var startupFailure: (any Error)? {
        failure.withLock { $0 }
    }

    public var activeConnections: Int {
        counts.withLock { $0.connections }
    }

    private var stopped: Bool {
        counts.withLock { $0.stopped }
    }

    public init(location: CommandEndpointLocation, receiver: CommandApplicationReceiver) {
        self.location = location; self.receiver = receiver
        Thread.detachNewThread { [self] in listen() }
    }

    public func stop() {
        counts.withLock { $0.stopped = true }
    }

    private func listen() {
        do {
            let listener = try CommandEndpointListener(location: location,
                                                       until: .now.advanced(by: .seconds(5)),
                                                       isCancelled: { self.stopped })
            defer { listener.close() }
            while !stopped {
                do {
                    let connection = try listener.accept(until: .now.advanced(by: .milliseconds(250)),
                                                         isCancelled: { self.stopped })
                    guard let permit = reserveConnection() else { connection.close(); continue }
                    let transferred = ConnectionTransfer(connection)
                    Thread.detachNewThread { [self] in
                        guard let owned = transferred.take() else { return }
                        defer { withExtendedLifetime(permit) {} }
                        serve(owned)
                    }
                } catch {
                    if stopped {
                        return
                    }
                    guard recoverableAcceptFailure(error) else { throw error }
                }
            }
        } catch {
            if !stopped {
                failure.withLock { $0 = error }
            }
        }
    }

    private func recoverableAcceptFailure(_ error: any Error) -> Bool {
        if case CommandEndpointError.invalidPeer = error {
            return true
        }
        guard let error = error as? CommandSocketError else { return false }
        switch error {
        case .timedOut, .closed: return true
        case let .unavailable(code) where [EPIPE, ECONNRESET, ECONNABORTED, ENOTCONN, EINTR, EAGAIN].contains(code):
            return true
        case let .unavailable(code) where [EMFILE, ENFILE, ENOBUFS].contains(code):
            Thread.sleep(forTimeInterval: 0.05)
            return true
        default: return false
        }
    }

    private func serve(_ connection: CommandSocketConnection) {
        let subscriber = UUID()
        defer {
            connection.close()
            Task { @MainActor [receiver] in receiver.disconnect(subscriber) }
        }
        do {
            if let mailbox = try prepare(connection, subscriber: subscriber) {
                try deliver(mailbox, subscriber: subscriber, on: connection)
            }
        } catch { /* Invalid, disconnected or expired input has no document callback. */ }
    }

    private func prepare(_ connection: CommandSocketConnection, subscriber: UUID) throws -> CommandReplyMailbox? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        guard let bytes = try connection.readFrame(until: deadline, isCancelled: { self.stopped }) else { return nil }
        let request = try CommandRequestCodec.decode(bytes)
        guard let inputPermit = reserveInput(request.stdin?.byteCount ?? 0) else {
            try reject(request, on: connection); return nil
        }
        let input = try receive(request, on: connection, until: deadline)
        try connection.verifyIdlePeer()
        let mailbox = CommandReplyMailbox()
        try CommandMainActorCall.perform(until: .now.advanced(by: .seconds(5)),
                                         isCancelled: { self.stopped }, operation: { [receiver] in
                                             try receiver.submit(input, subscriber: subscriber, mailbox: mailbox,
                                                                 retaining: { withExtendedLifetime(inputPermit) {} })
                                         })
        return mailbox
    }

    private func receive(_ request: CommandOpenRequest, on connection: CommandSocketConnection,
                         until deadline: ContinuousClock.Instant) throws -> CommandValidatedInput {
        guard let descriptor = request.stdin else { return try CommandValidatedInput(request: request, bytes: nil) }
        var input = try CommandStdinAccumulator(descriptor: descriptor)
        while let frame = try connection.readFrame(until: deadline, isCancelled: { self.stopped }) {
            if case let .complete(bytes) = try input.receive(frame) {
                return try CommandValidatedInput(request: request, bytes: bytes)
            }
        }
        throw CommandProtocolError.truncatedInput
    }

    private func deliver(
        _ mailbox: CommandReplyMailbox,
        subscriber: UUID,
        on connection: CommandSocketConnection
    ) throws {
        let acceptance = ContinuousClock.now.advanced(by: .seconds(40))
        var sentAccepted = false
        while !stopped {
            try connection.verifyIdlePeer()
            if let snapshot = mailbox.snapshot, !snapshot.events.isEmpty {
                for event in snapshot.events {
                    if case .accepted = event {
                        if sentAccepted {
                            continue
                        }
                        sentAccepted = true
                    }
                    try connection.writeFrame(CommandReplyCodec.encode(event),
                                              until: .now.advanced(by: .seconds(5)), isCancelled: { self.stopped })
                }
                if snapshot.isTerminal {
                    Task { @MainActor [receiver] in receiver.acknowledge(subscriber, terminal: true) }
                    return
                }
            }
            if !sentAccepted, ContinuousClock.now >= acceptance {
                throw CommandSocketError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        throw CommandSocketError.cancelled
    }

    private func reject(_ request: CommandOpenRequest, on connection: CommandSocketConnection) throws {
        try connection.writeFrame(CommandReplyCodec.encode(.rejected(requestID: request.id, reason: .unavailable)),
                                  until: .now.advanced(by: .seconds(1)), isCancelled: { self.stopped })
    }

    private func reserveConnection() -> Permit? {
        let admitted = counts.withLock { state in
            guard !state.stopped, state.connections < CommandReceiptLedger.maximumSubscribers else { return false }
            state.connections += 1; return true
        }
        return admitted ? Permit { [self] in counts.withLock { $0.connections -= 1 } } : nil
    }

    private func reserveInput(_ bytes: Int) -> Permit? {
        let admitted = counts.withLock { state in
            guard !state.stopped, state.inputs < CommandReceiptLedger.maximumPreparingRequests,
                  bytes <= CommandReceiptLedger.maximumInputBytes - state.bytes else { return false }
            state.inputs += 1; state.bytes += bytes; return true
        }
        return admitted ? Permit { [self] in counts.withLock { $0.inputs -= 1; $0.bytes -= bytes } } : nil
    }
}

private final class Permit: Sendable {
    let release: @Sendable () -> Void
    init(release: @escaping @Sendable () -> Void) {
        self.release = release
    }

    deinit { release() }
}

/// The receiving thread consumes this slot exactly once. The socket itself
/// remains intentionally non-Sendable and is never concurrently borrowed.
private final class ConnectionTransfer: Sendable {
    private let value: Mutex<CommandSocketConnection?>
    init(_ connection: sending CommandSocketConnection) {
        value = Mutex(connection)
    }

    func take() -> sending CommandSocketConnection? {
        value.withLock { $0.take() }
    }
}

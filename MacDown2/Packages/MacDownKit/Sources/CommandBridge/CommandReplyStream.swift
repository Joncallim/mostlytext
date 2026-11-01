import Foundation

public enum CommandReplyState: Sendable, Equatable {
    case awaitingAcceptance
    case waiting(openedCount: Int, failures: [CommandOpenFailure])
    case finished(openedCount: Int, failures: [CommandOpenFailure])
    case rejected(CommandOpenFailure.Reason)
    case failed

    public var isTerminal: Bool {
        switch self {
        case .finished, .rejected: true
        case .awaitingAcceptance, .waiting, .failed: false
        }
    }
}

/// One connection's ordered replies, bound to the exact original request.
/// Invalid input poisons this stream; callers cannot resume after a protocol error.
public struct CommandReplyStream: Sendable {
    public private(set) var state = CommandReplyState.awaitingAcceptance
    private let requestID: UUID
    private let waits: Bool
    private let targets: Set<CommandOpenTarget>

    public init(request: CommandOpenRequest) {
        requestID = request.id
        waits = request.wait
        var targets = Set(request.paths.indices.map(CommandOpenTarget.path))
        if request.stdin != nil {
            targets.insert(.stdin)
        }
        if targets.isEmpty {
            targets.insert(.activation)
        }
        self.targets = targets
    }

    public mutating func receive(_ bytes: Data) throws {
        do {
            try receive(CommandReplyCodec.decode(bytes))
        } catch {
            state = .failed
            throw error
        }
    }

    public mutating func receive(_ event: CommandReceiptEvent) throws {
        do {
            switch (state, event) {
            case let (.awaitingAcceptance, .accepted(id, count, failures)):
                let failed = Set(failures.map(\.target))
                let remaining = targets.count - failed.count
                guard id == requestID, failed.count == failures.count, failed.isSubset(of: targets),
                      remaining == 0 ? count == 0 : (1 ... remaining).contains(count) else {
                    throw CommandProtocolError.invalidResponse
                }
                state = waits ? .waiting(openedCount: count, failures: failures)
                    : .finished(openedCount: count, failures: failures)
            case let (.awaitingAcceptance, .rejected(id, reason)) where id == requestID:
                state = .rejected(reason)
            case let (.waiting(count, failures), .finished(id)) where id == requestID:
                state = .finished(openedCount: count, failures: failures)
            default:
                throw CommandProtocolError.invalidResponse
            }
        } catch {
            state = .failed
            throw error
        }
    }

    /// EOF while waiting is unavailable, never evidence that a document closed.
    public mutating func finish() throws {
        guard state.isTerminal else {
            state = .failed
            throw CommandProtocolError.truncatedInput
        }
    }
}

import Foundation

public enum CommandOpenTarget: Sendable, Hashable {
    case path(Int)
    case stdin
    case activation
}

public struct CommandOpenFailure: Sendable, Equatable {
    public enum Reason: String,
        Sendable { case missingFile, unreadable, invalidEncoding, recoveryUnavailable, unavailable }
    public let target: CommandOpenTarget
    public let reason: Reason

    public init(target: CommandOpenTarget, reason: Reason) {
        self.target = target; self.reason = reason
    }
}

public struct CommandReceiptToken: Sendable, Hashable {
    public let requestID: UUID
    let ledgerID: UUID
    let reservationID: UUID
}

public enum CommandReservation: Sendable, Equatable {
    case admitted(CommandReceiptToken)
    case replay(CommandReceiptToken)

    public var token: CommandReceiptToken {
        switch self {
        case let .admitted(token), let .replay(token): token
        }
    }
}

public enum CommandReceiptEvent: Sendable, Equatable {
    case accepted(requestID: UUID, openedCount: Int, failures: [CommandOpenFailure])
    case finished(requestID: UUID)
    case rejected(requestID: UUID, reason: CommandOpenFailure.Reason)
}

public struct CommandReceiptSnapshot: Sendable, Equatable {
    public let events: [CommandReceiptEvent]
    public let isTerminal: Bool
}

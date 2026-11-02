import Foundation

public enum CommandClientOutcome: Sendable, Equatable {
    case finished(openedCount: Int, failures: [CommandOpenFailure])
    case rejected(CommandOpenFailure.Reason)
}

/// One off-main serialized owner transfers connection ownership for one
/// exchange. Every exit closes it. There is no automatic retry or relaunch.
public enum CommandClientExchange {
    public static func execute(
        _ request: CommandOpenRequest,
        stdin: Data?,
        endpoint: CommandConnectedEndpoint,
        inputDeadline: ContinuousClock.Instant,
        acceptanceDeadline: ContinuousClock.Instant,
        isCancelled: () -> Bool = { false }
    ) throws -> CommandClientOutcome {
        let connection = endpoint.connection
        defer { connection.close() }
        try check(inputDeadline: inputDeadline, acceptanceDeadline: acceptanceDeadline, isCancelled: isCancelled)
        try validate(stdin, for: request)
        let metadata = try CommandRequestCodec.encode(request)
        try check(inputDeadline: inputDeadline, acceptanceDeadline: acceptanceDeadline, isCancelled: isCancelled)
        try connection.writeFrame(metadata, until: inputDeadline, isCancelled: isCancelled)
        if let stdin {
            var offset = stdin.startIndex
            while offset < stdin.endIndex {
                let end = stdin.index(offset, offsetBy: min(CommandProtocol.maximumFrameBytes,
                                                            stdin.distance(from: offset, to: stdin.endIndex)))
                try connection.writeFrame(Data(stdin[offset ..< end]), until: inputDeadline, isCancelled: isCancelled)
                offset = end
            }
            try connection.writeFrame(Data(), until: inputDeadline, isCancelled: isCancelled)
        }
        var replies = CommandReplyStream(request: request)
        while true {
            let deadline: ContinuousClock.Instant? = replies.state == .awaitingAcceptance ? acceptanceDeadline : nil
            guard let bytes = try connection.readFrame(until: deadline, isCancelled: isCancelled) else {
                try replies.finish()
                throw CommandProtocolError.invalidState
            }
            try replies.receive(bytes)
            switch replies.state {
            case let .finished(count, failures): return .finished(openedCount: count, failures: failures)
            case let .rejected(reason): return .rejected(reason)
            case .waiting: continue
            case .awaitingAcceptance, .failed: throw CommandProtocolError.invalidState
            }
        }
    }

    private static func validate(_ bytes: Data?, for request: CommandOpenRequest) throws {
        switch (request.stdin, bytes) {
        case (nil, nil): return
        case let (descriptor?, bytes?):
            guard descriptor.byteCount == bytes.count else { throw CommandProtocolError.stdinLengthMismatch }
            guard try CommandStdinDescriptor(bytes: bytes) == descriptor else {
                throw CommandProtocolError.stdinDigestMismatch
            }
            guard String(data: bytes, encoding: .utf8) != nil else { throw CommandProtocolError.invalidUTF8 }
        default: throw CommandProtocolError.invalidStdinDescriptor
        }
    }

    private static func check(inputDeadline: ContinuousClock.Instant,
                              acceptanceDeadline: ContinuousClock.Instant,
                              isCancelled: () -> Bool) throws {
        if isCancelled() {
            throw CommandSocketError.cancelled
        }
        guard ContinuousClock.now < inputDeadline, ContinuousClock.now < acceptanceDeadline else {
            throw CommandSocketError.timedOut
        }
    }
}

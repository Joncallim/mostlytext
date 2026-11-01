import CommandBridge
import Darwin
import Foundation
import Synchronization
import Testing

struct CommandClientExchangeTests {
    @Test func bareAndPathRequestsReturnOnlyAfterValidatedAcceptance() throws {
        for paths in [[], ["/space path/漢\n$().md"]] {
            let request = try CommandOpenRequest(paths: paths)
            let pair = try ExchangePair { peer in
                let received = try ExchangePair.readRequest(peer)
                #expect(try CommandRequestCodec.encode(received) == CommandRequestCodec.encode(request))
                try ExchangePair.reply(.accepted(requestID: request.id, openedCount: 1, failures: []), to: peer)
                #expect(try peer.readFrame(until: .now.advanced(by: .seconds(5))) == nil)
            }
            #expect(try pair.execute(request) == .finished(openedCount: 1, failures: []))
            #expect(throws: CommandSocketError.closed) { try pair.client.readFrame(until: nil) }
            try pair.server.finish()
        }
    }

    @Test(arguments: [
        Data(), Data([239, 187, 191]) + Data("Café 漢\r\n".utf8),
        Data(repeating: 65, count: CommandProtocol.maximumFrameBytes * 2 + 7),
    ])
    func stdinRetainsExactBytesAndHasOneExplicitTerminator(_ body: Data) throws {
        let bytes = (Data("skip".utf8) + body).dropFirst(4)
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: bytes))
        let pair = try ExchangePair { peer in
            let received = try ExchangePair.readRequest(peer)
            let descriptor = try #require(received.stdin)
            var incoming = try CommandStdinAccumulator(descriptor: descriptor)
            var count = 0
            while true {
                let chunk = try #require(try peer.readFrame(until: .now.advanced(by: .seconds(5))))
                count += 1
                #expect(chunk.count <= CommandProtocol.maximumFrameBytes)
                if case let .complete(value) = try incoming.receive(chunk) {
                    #expect(value == body)
                    #expect(count == (body.count + CommandProtocol.maximumFrameBytes - 1) /
                        CommandProtocol.maximumFrameBytes + 1)
                    break
                }
            }
            try ExchangePair.reply(.accepted(requestID: request.id, openedCount: 1, failures: []), to: peer)
            #expect(try peer.readFrame(until: .now.advanced(by: .seconds(5))) == nil)
        }
        #expect(try pair.execute(request, stdin: bytes) == .finished(openedCount: 1, failures: []))
        try pair.server.finish()
    }

    @Test func undeclaredMissingWrongLengthWrongDigestAndInvalidUTF8SendNothing() throws {
        let bytes = Data("body".utf8)
        let declared = try CommandStdinDescriptor(bytes: bytes)
        let invalid = Data([255])
        let cases: [InvalidStdinCase] = try [
            .init(descriptor: nil, body: Data(), failure: .invalidStdinDescriptor),
            .init(descriptor: declared, body: nil, failure: .invalidStdinDescriptor),
            .init(descriptor: declared, body: Data([65]), failure: .stdinLengthMismatch),
            .init(descriptor: declared, body: Data("Body".utf8), failure: .stdinDigestMismatch),
            .init(descriptor: CommandStdinDescriptor(bytes: invalid), body: invalid, failure: .invalidUTF8),
        ]
        for invalid in cases {
            let request = try CommandOpenRequest(paths: [], stdin: invalid.descriptor)
            let pair = try ExchangePair { peer in
                let frame = try peer.readFrame(until: .now.advanced(by: .seconds(5)))
                #expect(frame == nil)
            }
            #expect(throws: invalid.failure) { try pair.execute(request, stdin: invalid.body) }
            #expect(throws: CommandSocketError.closed) { try pair.client.readFrame(until: nil) }
            try pair.server.finish()
        }
    }

    @Test func partialFailureAndRejectionRemainTypedResults() throws {
        let request = try CommandOpenRequest(paths: ["/one", "/two"])
        let failures = [CommandOpenFailure(target: .path(1), reason: .missingFile)]
        for rejected in [false, true] {
            let pair = try ExchangePair { peer in
                _ = try ExchangePair.readRequest(peer)
                try ExchangePair.reply(rejected ? .rejected(requestID: request.id, reason: .unavailable)
                    : .accepted(requestID: request.id, openedCount: 1, failures: failures), to: peer)
            }
            #expect(try pair.execute(request) == (rejected ? .rejected(.unavailable)
                    : .finished(openedCount: 1, failures: failures)))
            try pair.server.finish()
        }
    }

    @Test func waitContinuesPastTheAcceptanceDeadline() throws {
        let request = try CommandOpenRequest(paths: [], wait: true)
        let pair = try ExchangePair { peer in
            _ = try ExchangePair.readRequest(peer)
            try ExchangePair.reply(.accepted(requestID: request.id, openedCount: 1, failures: []), to: peer)
            // Deliberately longer than the acceptance deadline. Once accepted,
            // an editing lifetime has cancellation polling but no short timeout.
            usleep(750_000)
            try ExchangePair.reply(.finished(requestID: request.id), to: peer)
        }
        #expect(try pair.execute(request, acceptanceDeadline: .now.advanced(by: .milliseconds(500))) ==
            .finished(openedCount: 1, failures: []))
        try pair.server.finish()
    }

    @Test func closeBeforeAcceptanceOrDuringWaitIsNeverCompletion() throws {
        for accepts in [false, true] {
            let request = try CommandOpenRequest(paths: [], wait: true)
            let pair = try ExchangePair { peer in
                _ = try ExchangePair.readRequest(peer)
                if accepts {
                    try ExchangePair.reply(.accepted(requestID: request.id, openedCount: 1, failures: []), to: peer)
                }
            }
            #expect(throws: CommandProtocolError.truncatedInput) { try pair.execute(request) }
            #expect(throws: CommandSocketError.closed) { try pair.client.readFrame(until: nil) }
            try pair.server.finish()
        }
    }

    @Test func wrongIDFinishedFirstDuplicateAcceptanceAndMalformedReplyCloseTheConnection() throws {
        let request = try CommandOpenRequest(paths: [], wait: true)
        let accepted = CommandReceiptEvent.accepted(requestID: request.id, openedCount: 1, failures: [])
        let cases = try [
            [CommandReplyCodec.encode(.finished(requestID: request.id))],
            [CommandReplyCodec.encode(.accepted(requestID: UUID(), openedCount: 1, failures: []))],
            [CommandReplyCodec.encode(accepted), CommandReplyCodec.encode(accepted)],
            [Data("{\"broken\":true}".utf8)],
        ]
        for frames in cases {
            let pair = try ExchangePair { peer in
                _ = try ExchangePair.readRequest(peer)
                for bytes in frames {
                    try peer.writeFrame(bytes, until: .now.advanced(by: .seconds(5)))
                }
                #expect(try peer.readFrame(until: .now.advanced(by: .seconds(5))) == nil)
            }
            #expect(throws: CommandProtocolError.self) { try pair.execute(request) }
            try pair.server.finish()
        }
    }

    @Test func stalledAcceptanceTimesOutAndCloses() throws {
        let request = try CommandOpenRequest(paths: [])
        let pair = try ExchangePair { peer in
            _ = try ExchangePair.readRequest(peer)
            #expect(try peer.readFrame(until: .now.advanced(by: .seconds(5))) == nil)
        }
        #expect(throws: CommandSocketError.timedOut) {
            try pair.execute(request, acceptanceDeadline: .now.advanced(by: .milliseconds(100)))
        }
        try pair.server.finish()
    }

    @Test func alreadyCancelledOrExpiredExchangeSendsNothing() throws {
        let request = try CommandOpenRequest(paths: [])
        for cancelled in [false, true] {
            let pair = try ExchangePair { peer in
                let frame = try peer.readFrame(until: .now.advanced(by: .seconds(5)))
                #expect(frame == nil)
            }
            #expect(throws: cancelled ? CommandSocketError.cancelled : .timedOut) {
                try pair.execute(request, inputDeadline: .now.advanced(by: .seconds(-1)), isCancelled: { cancelled })
            }
            try pair.server.finish()
        }
    }

    @Test func cancellationDuringWaitClosesWithoutReportingFinished() throws {
        let request = try CommandOpenRequest(paths: [], wait: true)
        let cancelled = Mutex(false)
        let pair = try ExchangePair { peer in
            _ = try ExchangePair.readRequest(peer)
            try ExchangePair.reply(.accepted(requestID: request.id, openedCount: 1, failures: []), to: peer)
            usleep(100_000)
            cancelled.withLock { $0 = true }
            #expect(try peer.readFrame(until: .now.advanced(by: .seconds(5))) == nil)
        }
        #expect(throws: CommandSocketError.cancelled) {
            try pair.execute(request, isCancelled: { cancelled.withLock { $0 } })
        }
        try pair.server.finish()
    }

    @Test func stalledInputUsesTheOriginalFiniteDeadlineAcrossChunks() throws {
        let bytes = Data(repeating: 65, count: 2 * 1024 * 1024)
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: bytes))
        let pair = try ExchangePair { peer in
            // Do not drain the input until well after the client's deadline.
            usleep(300_000)
            do {
                while try peer.readFrame(until: .now.advanced(by: .seconds(5))) != nil {}
            } catch CommandProtocolError.truncatedInput {
                // Deadline closure can leave a partially transmitted frame.
            }
        }
        #expect(throws: CommandSocketError.timedOut) {
            try pair.execute(request, stdin: bytes, inputDeadline: .now.advanced(by: .milliseconds(100)))
        }
        #expect(throws: CommandSocketError.closed) { try pair.client.readFrame(until: nil) }
        try pair.server.finish()
    }

    private struct InvalidStdinCase {
        let descriptor: CommandStdinDescriptor?
        let body: Data?
        let failure: CommandProtocolError
    }
}

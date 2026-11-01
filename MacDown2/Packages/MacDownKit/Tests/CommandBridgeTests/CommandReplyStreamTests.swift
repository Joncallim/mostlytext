import CommandBridge
import Foundation
import Testing

struct CommandReplyStreamTests {
    @Test func waitRetainsAcceptanceUntilDocumentCompletion() throws {
        let request = try CommandOpenRequest(paths: ["/a", "/b"], wait: true)
        let failure = CommandOpenFailure(target: .path(1), reason: .missingFile)
        var stream = CommandReplyStream(request: request)
        try stream.receive(.accepted(requestID: request.id, openedCount: 1, failures: [failure]))
        #expect(stream.state == .waiting(openedCount: 1, failures: [failure]))
        #expect(!stream.state.isTerminal)
        try stream.receive(.finished(requestID: request.id))
        #expect(stream.state == .finished(openedCount: 1, failures: [failure]))
        try stream.finish()
    }

    @Test func nonWaitAcceptanceAndInitialRejectionAreTerminal() throws {
        let request = try CommandOpenRequest(paths: [])
        var stream = CommandReplyStream(request: request)
        try stream.receive(.accepted(requestID: request.id, openedCount: 1, failures: []))
        #expect(stream.state.isTerminal)
        try stream.finish()
        var rejected = CommandReplyStream(request: request)
        try rejected.receive(.rejected(requestID: request.id, reason: .unavailable))
        #expect(rejected.state == .rejected(.unavailable))
        try rejected.finish()
    }

    @Test func allFailedWaitStillRequiresOrderedCompletion() throws {
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: Data()), wait: true)
        let failures = [CommandOpenFailure(target: .stdin, reason: .recoveryUnavailable)]
        var stream = CommandReplyStream(request: request)
        try stream.receive(.accepted(requestID: request.id, openedCount: 0, failures: failures))
        #expect(!stream.state.isTerminal)
        try stream.receive(.finished(requestID: request.id))
        #expect(stream.state == .finished(openedCount: 0, failures: failures))
    }

    @Test func deduplicatedPathsMayShareOneOpenedLifetime() throws {
        let request = try CommandOpenRequest(paths: ["/a", "/a", "/alias"], wait: true)
        var stream = CommandReplyStream(request: request)
        try stream.receive(.accepted(requestID: request.id, openedCount: 1, failures: []))
        try stream.receive(.finished(requestID: request.id))
        #expect(stream.state.isTerminal)
    }

    @Test func impossibleAccountingPoisonsTheConnection() throws {
        let request = try CommandOpenRequest(paths: ["/a"], wait: true)
        let invalid: [CommandReceiptEvent] = [
            .accepted(requestID: request.id, openedCount: -1, failures: []),
            .accepted(requestID: request.id, openedCount: 0, failures: []),
            .accepted(requestID: request.id, openedCount: 2, failures: []),
            .accepted(requestID: request.id, openedCount: 1, failures: [.init(target: .stdin, reason: .unavailable)]),
            .accepted(requestID: request.id, openedCount: 0, failures: [.init(target: .path(1), reason: .unavailable)]),
            .accepted(requestID: request.id, openedCount: 0, failures: [
                .init(target: .path(0), reason: .unavailable), .init(target: .path(0), reason: .unavailable),
            ]),
        ]
        for event in invalid {
            var stream = CommandReplyStream(request: request)
            #expect(throws: CommandProtocolError.invalidResponse) { try stream.receive(event) }
            #expect(stream.state == .failed)
            #expect(throws: CommandProtocolError.invalidResponse) {
                try stream.receive(.accepted(requestID: request.id, openedCount: 1, failures: []))
            }
        }
    }

    @Test func requestIDsAndEventOrderCannotBeSubstituted() throws {
        let request = try CommandOpenRequest(paths: [], wait: true)
        let invalidFirst: [CommandReceiptEvent] = [
            .finished(requestID: request.id), .finished(requestID: UUID()),
            .rejected(requestID: UUID(), reason: .unavailable),
            .accepted(requestID: UUID(), openedCount: 1, failures: []),
        ]
        for event in invalidFirst {
            var stream = CommandReplyStream(request: request)
            #expect(throws: CommandProtocolError.invalidResponse) { try stream.receive(event) }
        }
        let invalidNext: [CommandReceiptEvent] = [
            .accepted(requestID: request.id, openedCount: 1, failures: []),
            .finished(requestID: UUID()), .rejected(requestID: request.id, reason: .unavailable),
        ]
        for event in invalidNext {
            var stream = CommandReplyStream(request: request)
            try stream.receive(.accepted(requestID: request.id, openedCount: 1, failures: []))
            #expect(throws: CommandProtocolError.invalidResponse) { try stream.receive(event) }
            #expect(stream.state == .failed)
        }
    }

    @Test func eofNeverImpersonatesADocumentClose() throws {
        let request = try CommandOpenRequest(paths: [], wait: true)
        var initial = CommandReplyStream(request: request)
        #expect(throws: CommandProtocolError.truncatedInput) { try initial.finish() }
        var waiting = CommandReplyStream(request: request)
        try waiting.receive(.accepted(requestID: request.id, openedCount: 1, failures: []))
        #expect(throws: CommandProtocolError.truncatedInput) { try waiting.finish() }
        #expect(waiting.state == .failed)
    }

    @Test func terminalStateRejectsFurtherData() throws {
        let request = try CommandOpenRequest(paths: [])
        var stream = CommandReplyStream(request: request)
        try stream.receive(.accepted(requestID: request.id, openedCount: 1, failures: []))
        #expect(throws: CommandProtocolError.invalidResponse) {
            try stream.receive(.finished(requestID: request.id))
        }
        #expect(stream.state == .failed)
    }

    @Test func malformedWireReplyPoisonsSubsequentAdmission() throws {
        let request = try CommandOpenRequest(paths: [])
        var stream = CommandReplyStream(request: request)
        #expect(throws: CommandProtocolError.invalidResponse) { try stream.receive(Data([0xFF])) }
        #expect(stream.state == .failed)
        let valid = try CommandReplyCodec.encode(.accepted(requestID: request.id, openedCount: 1, failures: []))
        #expect(throws: CommandProtocolError.invalidResponse) { try stream.receive(valid) }
    }

    @Test func closeBeforeAcknowledgementSurvivesFramingAndReplay() throws {
        let request = try CommandOpenRequest(paths: ["/a"], wait: true)
        let subscriber = UUID()
        let lifetime = UUID()
        var ledger = CommandReceiptLedger()
        let reservation = try ledger.reserve(request, subscriber: subscriber)
        try ledger.bind(reservation.token, target: .path(0), lifetime: lifetime)
        ledger.documentClosed(lifetime)
        try ledger.completeOpening(reservation.token)
        let snapshot = try ledger.snapshot(reservation.token, subscriber: subscriber)
        #expect(snapshot.events.count == 2)
        let combined = try snapshot.events.reduce(into: Data()) { bytes, event in
            try bytes.append(CommandFrameDecoder.encode(CommandReplyCodec.encode(event)))
        }
        var decoder = CommandFrameDecoder()
        var stream = CommandReplyStream(request: request)
        var remaining = combined
        while !remaining.isEmpty {
            let consumed = try decoder.consume(remaining)
            remaining = remaining.dropFirst(consumed.consumedBytes)
            if let frame = consumed.frame {
                try stream.receive(frame)
            }
        }
        try decoder.finish()
        try stream.finish()
        #expect(stream.state == .finished(openedCount: 1, failures: []))
    }
}

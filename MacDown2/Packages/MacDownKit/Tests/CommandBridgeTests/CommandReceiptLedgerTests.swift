import CommandBridge
import Foundation
import Testing

struct CommandReceiptLedgerTests {
    @Test func closeBeforeAcceptanceIsRetainedAndOrderedAfterTheAcknowledgement() throws {
        var ledger = CommandReceiptLedger()
        let client = UUID(); let lifetime = UUID()
        let request = try CommandOpenRequest(paths: ["/a", "/alias"], wait: true)
        let token = try ledger.reserve(request, subscriber: client).token
        #expect(try ledger.snapshot(token, subscriber: client).events.isEmpty)
        try ledger.bind(token, target: .path(0), lifetime: lifetime)
        ledger.documentClosed(lifetime)
        try ledger.bind(token, target: .path(1), lifetime: lifetime)
        try ledger.completeOpening(token)
        let final = try ledger.snapshot(token, subscriber: client)
        #expect(final.events == [
            .accepted(requestID: request.id, openedCount: 1, failures: []),
            .finished(requestID: request.id),
        ])
        #expect(final.isTerminal)
        ledger.documentClosed(lifetime)
        #expect(try ledger.snapshot(token, subscriber: client).events.count == 2)
        #expect(ledger.preparingRequests == 0)
    }

    @Test func acceptanceRemainsAnImmutablePrefixUntilEveryLogicalLifetimeCloses() throws {
        var ledger = CommandReceiptLedger()
        let client = UUID(); let first = UUID(); let second = UUID()
        let request = try CommandOpenRequest(paths: ["/a", "/b"], wait: true)
        let token = try ledger.reserve(request, subscriber: client).token
        try ledger.bind(token, target: .path(0), lifetime: first)
        try ledger.bind(token, target: .path(1), lifetime: second)
        try ledger.completeOpening(token)
        let initial = try ledger.snapshot(token, subscriber: client)
        #expect(!initial.isTerminal)
        #expect(initial.events == [.accepted(requestID: request.id, openedCount: 2, failures: [])])
        #expect(throws: CommandProtocolError.invalidTransition) {
            try ledger.acknowledgeDelivery(token, subscriber: client, terminal: true)
        }
        ledger.documentClosed(first)
        #expect(try ledger.snapshot(token, subscriber: client) == initial)
        ledger.documentClosed(second)
        let final = try ledger.snapshot(token, subscriber: client)
        #expect(final.isTerminal)
        #expect(Array(final.events.prefix(initial.events.count)) == initial.events)
        #expect(initial.events.count == 1)
        try ledger.acknowledgeDelivery(token, subscriber: client, terminal: false)
        #expect(ledger.subscriberCount == 1)
        try ledger.acknowledgeDelivery(token, subscriber: client, terminal: true)
        #expect(ledger.subscriberCount == 0)
    }

    @Test func retriesJoinOneReceiptAndDisconnectDoesNotRemoveAnotherWaiter() throws {
        var ledger = CommandReceiptLedger()
        let first = UUID(); let second = UUID(); let lifetime = UUID()
        let request = try CommandOpenRequest(paths: ["/a"], wait: true)
        let token = try ledger.reserve(request, subscriber: first).token
        #expect(try ledger.reserve(request, subscriber: second) == .replay(token))
        #expect(try ledger.reserve(request, subscriber: second) == .replay(token))
        #expect(ledger.preparingRequests == 1)
        #expect(ledger.subscriberCount == 2)
        try ledger.bind(token, target: .path(0), lifetime: lifetime)
        try ledger.completeOpening(token)
        ledger.disconnect(first)
        #expect(throws: CommandProtocolError.invalidReceipt) { try ledger.snapshot(token, subscriber: first) }
        #expect(try !ledger.snapshot(token, subscriber: second).isTerminal)
        ledger.documentClosed(lifetime)
        #expect(try ledger.snapshot(token, subscriber: second).isTerminal)
        #expect(ledger.receiptCount == 1)
        #expect(ledger.subscriberCount == 1)
    }

    @Test func changedPayloadAndForeignLedgerTokensNeverReuseAuthority() throws {
        var ledger = CommandReceiptLedger(); var foreign = CommandReceiptLedger()
        let client = UUID(); let request = try CommandOpenRequest(paths: ["/é"])
        let token = try ledger.reserve(request, subscriber: client).token
        let changed = try CommandOpenRequest(id: request.id, paths: ["/e\u{301}"])
        #expect(throws: CommandProtocolError.reusedRequestID) { try ledger.reserve(changed, subscriber: UUID()) }
        _ = try foreign.reserve(request, subscriber: client)
        #expect(throws: CommandProtocolError.invalidReceipt) {
            try foreign.bind(token, target: .path(0), lifetime: UUID())
        }
        #expect(ledger.preparingRequests == 1)
        #expect(ledger.subscriberCount == 1)
    }

    @Test func everyTargetMustBeAccountedForAndAdmittedSourceCannotBeRejected() throws {
        var ledger = CommandReceiptLedger(); let client = UUID()
        let request = try CommandOpenRequest(paths: ["/a", "/missing"], stdin: CommandStdinDescriptor(bytes: Data()))
        let token = try ledger.reserve(request, subscriber: client).token
        let lifetime = UUID()
        try ledger.bind(token, target: .path(0), lifetime: lifetime)
        #expect(throws: CommandProtocolError.invalidTransition) { try ledger.completeOpening(token) }
        #expect(throws: CommandProtocolError.invalidTransition) { try ledger.reject(token, reason: .unavailable) }
        #expect(throws: CommandProtocolError.invalidTransition) {
            try ledger.bind(token, target: .path(0), lifetime: UUID())
        }
        #expect(throws: CommandProtocolError.invalidTransition) {
            try ledger.bind(token, target: .path(3), lifetime: UUID())
        }
        try ledger.bind(token, target: .stdin, lifetime: UUID())
        let failures = [CommandOpenFailure(target: .path(1), reason: .missingFile)]
        try ledger.completeOpening(token, failures: failures)
        #expect(try ledger.snapshot(token, subscriber: client).events == [
            .accepted(requestID: request.id, openedCount: 2, failures: failures),
        ])
        #expect(ledger.preparingRequests == 0)
        try ledger.acknowledgeDelivery(token, subscriber: client, terminal: false)
        #expect(ledger.subscriberCount == 0)
    }

    @Test func duplicateOrContradictoryFailuresDoNotReleaseThePreparingReservation() throws {
        var ledger = CommandReceiptLedger(); let client = UUID()
        let request = try CommandOpenRequest(paths: ["/a", "/b"])
        let token = try ledger.reserve(request, subscriber: client).token
        try ledger.bind(token, target: .path(0), lifetime: UUID())
        let failure = CommandOpenFailure(target: .path(0), reason: .unreadable)
        #expect(throws: CommandProtocolError.invalidTransition) {
            try ledger.completeOpening(token, failures: [failure])
        }
        let missing = CommandOpenFailure(target: .path(1), reason: .missingFile)
        #expect(throws: CommandProtocolError.invalidTransition) {
            try ledger.completeOpening(token, failures: [missing, missing])
        }
        #expect(ledger.preparingRequests == 1)
        #expect(try ledger.snapshot(token, subscriber: client).events.isEmpty)
        try ledger.completeOpening(token, failures: [missing])
        #expect(throws: CommandProtocolError.invalidTransition) {
            try ledger.completeOpening(token, failures: [missing])
        }
        #expect(ledger.preparingRequests == 0)
    }

    @Test func separatelyNamedRequestsCanWaitForTheSameStableLogicalLifetime() throws {
        var ledger = CommandReceiptLedger(); let lifetime = UUID()
        let first = UUID(); let second = UUID()
        let before = try ledger.reserve(CommandOpenRequest(paths: ["/before-save-as"], wait: true), subscriber: first)
            .token
        let after = try ledger.reserve(CommandOpenRequest(paths: ["/after-save-as"], wait: true), subscriber: second)
            .token
        for token in [before, after] {
            try ledger.bind(token, target: .path(0), lifetime: lifetime)
            try ledger.completeOpening(token)
        }
        #expect(try !ledger.snapshot(before, subscriber: first).isTerminal)
        #expect(try !ledger.snapshot(after, subscriber: second).isTerminal)
        ledger.documentClosed(lifetime)
        #expect(try ledger.snapshot(before, subscriber: first).isTerminal)
        #expect(try ledger.snapshot(after, subscriber: second).isTerminal)
    }
}

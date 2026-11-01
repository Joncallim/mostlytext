import CommandBridge
import Foundation
import Testing

struct CommandReceiptCapacityTests {
    @Test func preparingCapacityIsReleasedOnlyByActualCompletion() throws {
        var ledger = CommandReceiptLedger(); var tokens: [CommandReceiptToken] = []
        let client = UUID()
        for _ in 0 ..< CommandReceiptLedger.maximumPreparingRequests {
            try tokens.append(ledger.reserve(CommandOpenRequest(paths: []), subscriber: client).token)
        }
        #expect(throws: CommandProtocolError.requestCapacity) {
            try ledger.reserve(CommandOpenRequest(paths: []), subscriber: UUID())
        }
        ledger.disconnect(client)
        #expect(ledger.preparingRequests == 8)
        #expect(ledger.subscriberCount == 0)
        let token = try #require(tokens.first)
        try ledger.reject(token, reason: .unavailable)
        _ = try ledger.reserve(CommandOpenRequest(paths: []), subscriber: UUID())
        #expect(ledger.preparingRequests == 8)
        #expect(throws: CommandProtocolError.invalidTransition) { try ledger.reject(token, reason: .unavailable) }
        #expect(ledger.preparingRequests == 8)
    }

    @Test func totalInputReservationIsBoundedWithoutAllocatingTheDeclaredBodies() throws {
        var ledger = CommandReceiptLedger(); let client = UUID()
        let full = try CommandStdinDescriptor(byteCount: CommandProtocol.maximumStdinBytes,
                                              sha256: String(repeating: "a", count: 64))
        let first = try ledger.reserve(CommandOpenRequest(paths: [], stdin: full), subscriber: client).token
        _ = try ledger.reserve(CommandOpenRequest(paths: [], stdin: full), subscriber: UUID())
        #expect(ledger.inputBytes == CommandReceiptLedger.maximumInputBytes)
        let one = try CommandStdinDescriptor(byteCount: 1, sha256: String(repeating: "b", count: 64))
        #expect(throws: CommandProtocolError.inputCapacity) {
            try ledger.reserve(CommandOpenRequest(paths: [], stdin: one), subscriber: UUID())
        }
        ledger.disconnect(client)
        #expect(ledger.inputBytes == CommandReceiptLedger.maximumInputBytes)
        try ledger.reject(first, reason: .unavailable)
        #expect(ledger.inputBytes == CommandProtocol.maximumStdinBytes)
        _ = try ledger.reserve(CommandOpenRequest(paths: [], stdin: full), subscriber: UUID())
        #expect(ledger.inputBytes == CommandReceiptLedger.maximumInputBytes)
    }

    @Test func replaySubscribersAreBoundedAndDisconnectFreesOnlyTheirSlot() throws {
        var ledger = CommandReceiptLedger()
        let request = try CommandOpenRequest(paths: [], wait: true)
        var clients: [UUID] = []
        for _ in 0 ..< CommandReceiptLedger.maximumSubscribers {
            let client = UUID(); clients.append(client)
            _ = try ledger.reserve(request, subscriber: client)
        }
        #expect(ledger.preparingRequests == 1)
        #expect(ledger.receiptCount == 1)
        #expect(ledger.subscriberCount == 128)
        #expect(throws: CommandProtocolError.subscriberCapacity) { try ledger.reserve(request, subscriber: UUID()) }
        try ledger.disconnect(#require(clients.first))
        _ = try ledger.reserve(request, subscriber: UUID())
        #expect(ledger.subscriberCount == 128)
        #expect(ledger.preparingRequests == 1)
    }

    @Test func retainedReceiptsReachAFiniteLimitAndExpireWithoutEvictingActiveWaiters() throws {
        var ledger = CommandReceiptLedger()
        let now = ContinuousClock.now
        let activeClient = UUID()
        let active = try ledger.reserve(CommandOpenRequest(paths: [], wait: true), subscriber: activeClient, now: now)
            .token
        try ledger.bind(active, target: .activation, lifetime: UUID(), now: now)
        try ledger.completeOpening(active, now: now)
        for _ in 1 ..< CommandReceiptLedger.maximumReceipts {
            let client = UUID()
            let token = try ledger.reserve(CommandOpenRequest(paths: []), subscriber: client, now: now).token
            try ledger.reject(token, reason: .unavailable, now: now)
            try ledger.acknowledgeDelivery(token, subscriber: client, terminal: true, now: now)
        }
        #expect(ledger.receiptCount == CommandReceiptLedger.maximumReceipts)
        #expect(throws: CommandProtocolError.receiptCapacity) {
            try ledger.reserve(CommandOpenRequest(paths: []), subscriber: UUID(), now: now)
        }
        #expect(ledger.prune(now: now.advanced(by: .seconds(299))) == 0)
        #expect(ledger.prune(now: now.advanced(by: .seconds(301))) == CommandReceiptLedger.maximumReceipts - 1)
        #expect(ledger.receiptCount == 1)
        #expect(try !ledger.snapshot(active, subscriber: activeClient).isTerminal)
        #expect(ledger.subscriberCount == 1)
    }

    @Test func aDisconnectedWaitReceiptMayExpireBeforeItsDocumentCloses() throws {
        var ledger = CommandReceiptLedger(); let now = ContinuousClock.now; let client = UUID(); let lifetime = UUID()
        let token = try ledger.reserve(CommandOpenRequest(paths: ["/fixture"], wait: true),
                                       subscriber: client, now: now).token
        try ledger.bind(token, target: .path(0), lifetime: lifetime, now: now)
        try ledger.completeOpening(token, now: now)
        ledger.disconnect(client, now: now)
        #expect(ledger.prune(now: now.advanced(by: .seconds(301))) == 1)
        #expect(ledger.receiptCount == 0)
        ledger.documentClosed(lifetime)
        #expect(ledger.inputBytes == 0)
        #expect(ledger.subscriberCount == 0)
    }

    @Test func disconnectedPreparingWorkerCannotBePrunedBeforeItsActualDrain() throws {
        var ledger = CommandReceiptLedger(); let now = ContinuousClock.now; let client = UUID()
        let descriptor = try CommandStdinDescriptor(bytes: Data("pending".utf8))
        let token = try ledger.reserve(CommandOpenRequest(paths: [], stdin: descriptor),
                                       subscriber: client, now: now).token
        ledger.disconnect(client, now: now)
        #expect(ledger.prune(now: now.advanced(by: .seconds(10000))) == 0)
        #expect(ledger.preparingRequests == 1)
        #expect(ledger.inputBytes == 7)
        try ledger.reject(token, reason: .unavailable, now: now)
        #expect(ledger.preparingRequests == 0)
        #expect(ledger.inputBytes == 0)
        #expect(ledger.prune(now: now.advanced(by: .seconds(301))) == 1)
    }
}

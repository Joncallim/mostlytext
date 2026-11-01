import Foundation

/// One serialized owner; this reducer retains IDs and digests, never source or document models.
public struct CommandReceiptLedger: Sendable {
    public static let maximumPreparingRequests = 8
    public static let maximumInputBytes = 64 * 1024 * 1024
    public static let maximumSubscribers = 128
    public static let maximumReceipts = 512
    public static let retention = Duration.seconds(300)

    enum Phase: Sendable { case preparing, accepted([CommandOpenFailure]), rejected(CommandOpenFailure.Reason) }
    struct Entry: Sendable {
        let token: CommandReceiptToken
        let fingerprint: String
        let inputBytes: Int
        let wait: Bool
        let targets: Set<CommandOpenTarget>
        var phase = Phase.preparing
        var subscribers: Set<UUID>
        var bindings: [CommandOpenTarget: UUID] = [:]
        var remaining: Set<UUID> = []
        var closed: Set<UUID> = []
        var lastActivity: ContinuousClock.Instant
    }

    let identity = UUID()
    var entries: [UUID: Entry] = [:]
    public private(set) var preparingRequests = 0
    public private(set) var inputBytes = 0
    public private(set) var subscriberCount = 0
    public var receiptCount: Int {
        entries.count
    }

    public init() {}

    public mutating func reserve(_ request: CommandOpenRequest, subscriber: UUID,
                                 now: ContinuousClock.Instant = .now) throws -> CommandReservation {
        let fingerprint = try CommandRequestCodec.fingerprint(request)
        prune(now: now)
        if var entry = entries[request.id] {
            guard entry.fingerprint == fingerprint else { throw CommandProtocolError.reusedRequestID }
            if !entry.subscribers.contains(subscriber) {
                guard subscriberCount < Self.maximumSubscribers else { throw CommandProtocolError.subscriberCapacity }
                entry.subscribers.insert(subscriber); subscriberCount += 1
            }
            entry.lastActivity = now; entries[request.id] = entry
            return .replay(entry.token)
        }
        guard entries.count < Self.maximumReceipts else { throw CommandProtocolError.receiptCapacity }
        guard preparingRequests < Self.maximumPreparingRequests else { throw CommandProtocolError.requestCapacity }
        let declared = request.stdin?.byteCount ?? 0
        guard declared <= Self.maximumInputBytes - inputBytes else { throw CommandProtocolError.inputCapacity }
        guard subscriberCount < Self.maximumSubscribers else { throw CommandProtocolError.subscriberCapacity }
        let token = CommandReceiptToken(requestID: request.id, ledgerID: identity)
        var targets = Set(request.paths.indices.map(CommandOpenTarget.path))
        if request.stdin != nil {
            targets.insert(.stdin)
        }
        if targets.isEmpty {
            targets.insert(.activation)
        }
        entries[request.id] = Entry(token: token, fingerprint: fingerprint, inputBytes: declared,
                                    wait: request.wait, targets: targets, subscribers: [subscriber], lastActivity: now)
        preparingRequests += 1; inputBytes += declared; subscriberCount += 1
        return .admitted(token)
    }

    public mutating func bind(_ token: CommandReceiptToken, target: CommandOpenTarget, lifetime: UUID,
                              now: ContinuousClock.Instant = .now) throws {
        var entry = try entry(for: token)
        guard case .preparing = entry.phase, entry.targets.contains(target) else {
            throw CommandProtocolError.invalidTransition
        }
        if let current = entry.bindings[target] {
            guard current == lifetime else { throw CommandProtocolError.invalidTransition }
            return
        }
        entry.bindings[target] = lifetime
        if !entry.closed.contains(lifetime) {
            entry.remaining.insert(lifetime)
        }
        entry.lastActivity = now; entries[token.requestID] = entry
    }

    public mutating func completeOpening(_ token: CommandReceiptToken, failures: [CommandOpenFailure] = [],
                                         now: ContinuousClock.Instant = .now) throws {
        var entry = try entry(for: token)
        guard case .preparing = entry.phase else { throw CommandProtocolError.invalidTransition }
        guard failures.count <= entry.targets.count else { throw CommandProtocolError.invalidTransition }
        let failedTargets = Set(failures.map(\.target))
        guard failedTargets.count == failures.count, failedTargets.isDisjoint(with: entry.bindings.keys),
              failedTargets.union(entry.bindings.keys) == entry.targets else {
            throw CommandProtocolError.invalidTransition
        }
        entry.phase = .accepted(failures)
        if !entry.wait {
            entry.remaining.removeAll()
        }
        entry.lastActivity = now; entries[token.requestID] = entry
        preparingRequests -= 1; inputBytes -= entry.inputBytes
    }

    public mutating func reject(_ token: CommandReceiptToken, reason: CommandOpenFailure.Reason,
                                now: ContinuousClock.Instant = .now) throws {
        var entry = try entry(for: token)
        guard case .preparing = entry.phase, entry.bindings.isEmpty else {
            throw CommandProtocolError.invalidTransition
        }
        entry.phase = .rejected(reason)
        entry.lastActivity = now; entries[token.requestID] = entry
        preparingRequests -= 1; inputBytes -= entry.inputBytes
    }

    public mutating func documentClosed(_ lifetime: UUID, now: ContinuousClock.Instant = .now) {
        for id in Array(entries.keys) {
            guard var entry = entries[id], entry.remaining.remove(lifetime) != nil else { continue }
            entry.closed.insert(lifetime); entry.lastActivity = now; entries[id] = entry
        }
    }

    public func snapshot(_ token: CommandReceiptToken, subscriber: UUID) throws -> CommandReceiptSnapshot {
        let entry = try entry(for: token)
        guard entry.subscribers.contains(subscriber) else { throw CommandProtocolError.invalidReceipt }
        return Self.snapshot(entry)
    }

    public mutating func acknowledgeDelivery(_ token: CommandReceiptToken, subscriber: UUID, terminal: Bool,
                                             now: ContinuousClock.Instant = .now) throws {
        var entry = try entry(for: token)
        guard entry.subscribers.contains(subscriber), !Self.snapshot(entry).events.isEmpty else {
            throw CommandProtocolError.invalidTransition
        }
        if terminal {
            guard Self.snapshot(entry).isTerminal else { throw CommandProtocolError.invalidTransition }
        } else if entry.wait {
            return
        }
        entry.subscribers.remove(subscriber); subscriberCount -= 1
        entry.lastActivity = now; entries[token.requestID] = entry
    }

    public mutating func disconnect(_ subscriber: UUID, now: ContinuousClock.Instant = .now) {
        for id in Array(entries.keys) {
            guard var entry = entries[id], entry.subscribers.remove(subscriber) != nil else { continue }
            subscriberCount -= 1; entry.lastActivity = now; entries[id] = entry
        }
    }

    @discardableResult
    public mutating func prune(now: ContinuousClock.Instant = .now) -> Int {
        let expired = entries.compactMap { id, entry -> UUID? in
            if case .preparing = entry.phase {
                return nil
            }
            return entry.subscribers.isEmpty && entry.lastActivity.duration(to: now) >= Self.retention ? id : nil
        }
        for id in expired {
            entries.removeValue(forKey: id)
        }
        return expired.count
    }

    private func entry(for token: CommandReceiptToken) throws -> Entry {
        guard token.ledgerID == identity, let entry = entries[token.requestID], entry.token == token else {
            throw CommandProtocolError.invalidReceipt
        }
        return entry
    }

    private static func snapshot(_ entry: Entry) -> CommandReceiptSnapshot {
        switch entry.phase {
        case .preparing: return CommandReceiptSnapshot(events: [], isTerminal: false)
        case let .rejected(reason):
            return CommandReceiptSnapshot(events: [.rejected(requestID: entry.token.requestID, reason: reason)],
                                          isTerminal: true)
        case let .accepted(failures):
            let acknowledgement = CommandReceiptEvent.accepted(requestID: entry.token.requestID,
                                                               openedCount: Set(entry.bindings.values).count,
                                                               failures: failures)
            let events: [CommandReceiptEvent] = entry.wait && entry.remaining.isEmpty
                ? [acknowledgement, .finished(requestID: entry.token.requestID)] : [acknowledgement]
            return CommandReceiptSnapshot(events: events, isTerminal: !entry.wait || entry.remaining.isEmpty)
        }
    }
}

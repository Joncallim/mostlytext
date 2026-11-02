import Foundation
import Synchronization

/// Immutable input is verified off MainActor before any document callback.
public struct CommandValidatedInput: Sendable {
    public let request: CommandOpenRequest
    public let bytes: Data?

    public init(request: CommandOpenRequest, bytes: Data?) throws {
        if let descriptor = request.stdin, let bytes {
            var input = try CommandStdinAccumulator(descriptor: descriptor)
            for offset in stride(from: 0, to: bytes.count, by: CommandProtocol.maximumFrameBytes) {
                _ = try input.receive(bytes.subdata(in: offset ..< min(bytes.count,
                                                                       offset + CommandProtocol.maximumFrameBytes)))
            }
            _ = try input.receive(Data())
        } else if request.stdin != nil || bytes != nil {
            throw CommandProtocolError.invalidStdinDescriptor
        }
        self.request = request; self.bytes = bytes
    }
}

public final class CommandReplyMailbox: Sendable {
    private let value = Mutex<CommandReceiptSnapshot?>(nil)
    public init() {}
    public var snapshot: CommandReceiptSnapshot? {
        value.withLock { $0 }
    }

    func publish(_ snapshot: CommandReceiptSnapshot) {
        value.withLock { $0 = snapshot }
    }
}

/// This owner lives beside the app's document/window transactions. Transport
/// threads see immutable inputs and event mailboxes, never document models.
@MainActor
public final class CommandApplicationReceiver {
    public typealias Handler = @MainActor @Sendable (CommandValidatedInput, CommandOpeningAdmission) async -> Void
    private var ledger = CommandReceiptLedger()
    private let handler: Handler
    private var observers: [UUID: (CommandReceiptToken, CommandReplyMailbox)] = [:]
    private var lifetimes: Set<UUID> = []
    private var accepting = true
    private var terminated = false

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func submit(_ input: CommandValidatedInput, subscriber: UUID, mailbox: CommandReplyMailbox,
                       retaining: @escaping @Sendable () -> Void = {}) throws {
        guard accepting else { throw CommandSocketError.closed }
        let reservation = try ledger.reserve(input.request, subscriber: subscriber)
        observers[subscriber] = (reservation.token, mailbox)
        publish()
        guard case .admitted = reservation else { return }
        let admission = CommandOpeningAdmission(owner: self, token: reservation.token, request: input.request)
        Task { @MainActor [handler] in
            defer { retaining() }
            await handler(input, admission)
            admission.finish()
        }
    }

    public func documentClosed(_ lifetime: UUID) {
        lifetimes.remove(lifetime)
        ledger.documentClosed(lifetime)
        publish()
    }

    public func disconnect(_ subscriber: UUID) {
        observers.removeValue(forKey: subscriber)
        ledger.disconnect(subscriber)
    }

    public func acknowledge(_ subscriber: UUID, terminal: Bool) {
        guard let (token, _) = observers[subscriber] else { return }
        do {
            try ledger.acknowledgeDelivery(token, subscriber: subscriber, terminal: terminal)
            if terminal {
                observers.removeValue(forKey: subscriber)
            }
        } catch { disconnect(subscriber) }
    }

    public func suspendAdmission() {
        accepting = false
    }

    public func resumeAdmission() {
        guard !terminated else { return }
        accepting = true
    }

    /// Call only after the app has accepted Quit and secured its session.
    public func finishForTermination() {
        terminated = true
        accepting = false
        for lifetime in lifetimes {
            ledger.documentClosed(lifetime)
        }
        lifetimes.removeAll()
        publish()
    }

    fileprivate var permitsAdmission: Bool {
        accepting
    }

    fileprivate func bind(_ token: CommandReceiptToken, target: CommandOpenTarget, lifetime: UUID) throws {
        guard accepting else { throw CommandSocketError.closed }
        try ledger.bind(token, target: target, lifetime: lifetime)
        lifetimes.insert(lifetime)
    }

    fileprivate func complete(_ token: CommandReceiptToken, failures: [CommandOpenFailure]) throws {
        try ledger.completeOpening(token, failures: failures)
        publish()
    }

    fileprivate func reject(_ token: CommandReceiptToken, reason: CommandOpenFailure.Reason) throws {
        try ledger.reject(token, reason: reason)
        publish()
    }

    private func publish() {
        for (subscriber, (token, mailbox)) in observers {
            if let snapshot = try? ledger.snapshot(token, subscriber: subscriber) {
                mailbox.publish(snapshot)
            }
        }
    }
}

@MainActor
public final class CommandOpeningAdmission {
    private let owner: CommandApplicationReceiver
    private let token: CommandReceiptToken
    private let targets: Set<CommandOpenTarget>
    private var bound: Set<CommandOpenTarget> = []
    private var failures: [CommandOpenTarget: CommandOpenFailure.Reason] = [:]
    private var finished = false

    fileprivate init(owner: CommandApplicationReceiver, token: CommandReceiptToken, request: CommandOpenRequest) {
        self.owner = owner; self.token = token
        var targets = Set(request.paths.indices.map(CommandOpenTarget.path))
        if request.stdin != nil {
            targets.insert(.stdin)
        }
        if targets.isEmpty {
            targets.insert(.activation)
        }
        self.targets = targets
    }

    public var canContinue: Bool {
        !finished && owner.permitsAdmission
    }

    /// False refuses exposure if the receipt no longer owns this admission.
    public func bind(_ target: CommandOpenTarget, lifetime: UUID) -> Bool {
        guard !finished, targets.contains(target), failures[target] == nil else { return false }
        do {
            try owner.bind(token, target: target, lifetime: lifetime)
            bound.insert(target)
            return true
        } catch { return false }
    }

    public func fail(_ target: CommandOpenTarget, reason: CommandOpenFailure.Reason) {
        guard !finished, targets.contains(target), !bound.contains(target) else { return }
        failures[target] = reason
    }

    public func reject(_ reason: CommandOpenFailure.Reason) {
        guard !finished, bound.isEmpty else { return }
        do { try owner.reject(token, reason: reason); finished = true } catch { finish() }
    }

    /// Any target omitted by the app is a failure, never an inferred open.
    public func finish() {
        guard !finished else { return }
        let failed = targets.subtracting(bound).map {
            CommandOpenFailure(target: $0, reason: failures[$0] ?? .unavailable)
        }.sorted { String(describing: $0.target) < String(describing: $1.target) }
        do { try owner.complete(token, failures: failed); finished = true } catch {
            // An invariant failure cannot publish a fabricated acceptance.
            finished = true
        }
    }
}

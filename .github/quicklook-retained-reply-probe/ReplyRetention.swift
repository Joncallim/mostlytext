import CryptoKit
import Darwin
import Foundation
import QuickLookUI
import Synchronization

private enum Terminal: Sendable { case replied, failed, cancelled }

private final class TerminalGate: Sendable {
    private let terminal = Mutex<Terminal?>(nil)

    func finish(_ value: Terminal) -> Bool {
        terminal.withLock { current in
            guard current == nil else { return false }
            current = value
            return true
        }
    }
}

private final class Ledger: Sendable {
    private let active = Mutex<[UUID: Int]>([:])
    let byteLimit = 64 * 1_048_576
    let holderLimit = 8

    func reserve(_ bytes: Int) -> Reservation? {
        guard bytes > 0, bytes <= byteLimit else { return nil }
        return active.withLock { entries in
            let used = entries.values.reduce(0, +)
            guard entries.count < holderLimit, bytes <= byteLimit - used else { return nil }
            let id = UUID()
            entries[id] = bytes
            return Reservation(id: id, ledger: self)
        }
    }

    fileprivate func release(_ id: UUID) -> Bool {
        active.withLock { $0.removeValue(forKey: id) != nil }
    }

    var usage: (holders: Int, bytes: Int) {
        active.withLock { ($0.count, $0.values.reduce(0, +)) }
    }
}

private final class Reservation: Sendable {
    private let id: UUID
    private let ledger: Ledger
    private let released = Mutex(false)

    init(id: UUID, ledger: Ledger) {
        self.id = id
        self.ledger = ledger
    }

    @discardableResult func release() -> Bool {
        released.withLock { done in
            guard !done else { return false }
            done = true
            return ledger.release(id)
        }
    }

    deinit { release() }
}

private final class Payload: Sendable {
    let bytes: Data
    let reservation: Reservation
    let calls = Mutex(0)

    init(index: Int, reservation: Reservation) {
        self.reservation = reservation
        var html = Data("<!doctype html><meta charset=utf-8><body>reply-\(index):".utf8)
        html.append(Data(repeating: 0x61 + UInt8(index), count: 1_048_576 - html.count - 7))
        html.append(Data("</body>".utf8))
        bytes = html
    }
}

private final class WeakPayload {
    weak var value: Payload?
    init(_ value: Payload) {
        self.value = value
    }
}

private final class HeldReply {
    var reply: QLPreviewReply?
    var factory: (@Sendable (QLPreviewReply) throws -> Data)?
    let observed: WeakPayload
    let digest: String

    init(reply: QLPreviewReply, factory: @escaping @Sendable (QLPreviewReply) throws -> Data,
         observed: WeakPayload, digest: String) {
        self.reply = reply
        self.factory = factory
        self.observed = observed
        self.digest = digest
    }
}

private struct ProbeFailure: Error { let condition: String }

private func require(_ value: @autoclosure () -> Bool, _ condition: String) throws {
    guard value() else { throw ProbeFailure(condition: condition) }
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func preparedReply(index: Int, ledger: Ledger) throws -> HeldReply {
    guard let reservation = ledger.reserve(1_048_576) else { throw ProbeFailure(condition: "initial-admission") }
    let holder = Payload(index: index, reservation: reservation)
    let factory: @Sendable (QLPreviewReply) throws -> Data = { [holder] _ in
        holder.calls.withLock { $0 += 1 }
        return holder.bytes
    }
    let reply = QLPreviewReply(
        dataOfContentType: .html,
        contentSize: CGSize(width: 640, height: 480),
        createDataUsing: factory
    )
    reply.stringEncoding = .utf8
    return HeldReply(reply: reply, factory: factory, observed: WeakPayload(holder), digest: digest(holder.bytes))
}

private func checkFactories(_ items: [HeldReply]) throws {
    for item in items {
        guard let reply = item.reply,
              let factory = item.factory else { throw ProbeFailure(condition: "missing-live-reply") }
        for _ in 0 ..< 3 {
            try autoreleasepool {
                let actual = try factory(reply)
                try require(actual.count == 1_048_576 && digest(actual) == item.digest, "factory-content-changed")
            }
        }
        try require(item.observed.value?.calls.withLock { $0 } == 3, "factory-restarted-or-missing")
    }
}

private func admissionControls() throws {
    let ledger = Ledger()
    try require(ledger.reserve(0) == nil && ledger.reserve(-1) == nil, "invalid-capacity-admitted")
    try require(ledger.reserve(Int.max) == nil, "overflow-capacity-admitted")
    guard let reservation = ledger.reserve(ledger.byteLimit)
    else { throw ProbeFailure(condition: "exact-limit-refused") }
    try require(ledger.reserve(1) == nil && ledger.usage.bytes == ledger.byteLimit, "byte-limit-not-enforced")
    try require(reservation.release() && !reservation.release(), "reservation-refunded-twice")
    try require(ledger.usage == (0, 0), "admission-control-leak")
}

private func runProbe() throws {
    try admissionControls()
    let ledger = Ledger()
    var held: [HeldReply] = []
    for index in 0 ..< 8 {
        let item = try autoreleasepool { try preparedReply(index: index, ledger: ledger) }
        held.append(item)
        let usage = ledger.usage
        print(
            "QL_RETENTION_OBSERVATION live=\(item.observed.value != nil) holders=\(usage.holders) bytes=\(usage.bytes)"
        )
        try require(
            item.observed.value != nil && usage == (index + 1, (index + 1) * 1_048_576),
            "retained-before-factory"
        )
    }
    try require(ledger.reserve(1_048_576) == nil && ledger.usage == (8, 8 * 1_048_576), "ninth-holder-admitted")
    for outcome in [Terminal.replied, .failed, .cancelled] {
        let terminal = TerminalGate()
        try require(terminal.finish(outcome), "initial-terminal-choice-refused")
        for late in [Terminal.replied, .failed, .cancelled] {
            try require(!terminal.finish(late), "late-terminal-choice-admitted")
        }
    }
    let otherRequest = TerminalGate()
    try require(otherRequest.finish(.cancelled) && !otherRequest.finish(.replied), "cancelled-request-replied")
    try checkFactories(held)
    try require(ledger.usage == (8, 8 * 1_048_576), "completion-refunded-retained-payload")
    let gate = TerminalGate()
    let winners = Mutex(0)
    DispatchQueue.concurrentPerform(iterations: 64) { index in
        if gate.finish(index.isMultiple(of: 3) ? .replied : index.isMultiple(of: 2) ? .failed : .cancelled) {
            winners.withLock { $0 += 1 }
        }
    }
    try require(winners.withLock { $0 } == 1, "more-than-one-terminal-result")
    for item in held {
        item.factory = nil
    }
    try require(
        held.allSatisfy { $0.observed.value != nil } && ledger.usage == (8, 8 * 1_048_576),
        "real-reply-does-not-retain-holder"
    )
    for (released, index) in [3, 0, 6, 1, 7, 2, 5, 4].enumerated() {
        autoreleasepool { held[index].reply = nil }
        try require(held[index].observed.value == nil, "reply-holder-retain-cycle")
        let remaining = 7 - released
        try require(ledger.usage == (remaining, remaining * 1_048_576), "wrong-drop-order-accounting")
    }
    try require(ledger.usage == (0, 0), "final-payload-leak")
    print("QL_RETENTION_PASS holders=8 payloadBytes=8388608 directFactoryCalls=24 exactDrops=8 terminalWinners=1")
}

@main private struct ReplyRetentionProbe {
    static func main() {
        guard let account = getpwuid(getuid()), getuid() == 501, getuid() == geteuid(),
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              CommandLine.arguments.count == 1,
              URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
              .hasPrefix("/Users/runner/work/_temp/quicklook-retained-reply/")
        else {
            print("QL_RETENTION_REFUSED foreign execution context")
            exit(77)
        }
        do {
            try runProbe()
        } catch let error as ProbeFailure {
            print("QL_RETENTION_FAILURE \(error.condition)")
            exit(error.condition == "retained-before-factory" ? 42 : 43)
        } catch {
            print("QL_RETENTION_UNEXPECTED \(String(describing: error))")
            exit(44)
        }
    }
}

import CommandBridge
import Foundation
import Synchronization

enum CommandLaunchWaiter {
    final class Ticket: Sendable {
        private let continuation: Mutex<CheckedContinuation<Void, any Error>?>

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = Mutex(continuation)
        }

        var isActive: Bool {
            continuation.withLock { $0 != nil }
        }

        func finish(_ result: Result<Void, any Error>) {
            let pending = continuation.withLock { value in
                let pending = value
                value = nil
                return pending
            }
            pending?.resume(with: result)
        }
    }

    static func wait(until deadline: ContinuousClock.Instant,
                     isCancelled: @escaping @Sendable () -> Bool,
                     start: @Sendable (Ticket) -> Void) async throws {
        if isCancelled() || Task.isCancelled {
            throw CommandSocketError.cancelled
        }
        guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
        let holder = Mutex<Ticket?>(nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let ticket = Ticket(continuation)
                holder.withLock { $0 = ticket }
                if Task.isCancelled {
                    ticket.finish(.failure(CommandSocketError.cancelled)); return
                }
                Task.detached { await poll(ticket, until: deadline, isCancelled: isCancelled) }
                start(ticket)
            }
        } onCancel: {
            holder.withLock { $0 }?.finish(.failure(CommandSocketError.cancelled))
        }
    }

    private static func poll(_ ticket: Ticket, until deadline: ContinuousClock.Instant,
                             isCancelled: @escaping @Sendable () -> Bool) async {
        while ticket.isActive {
            if isCancelled() {
                ticket.finish(.failure(CommandSocketError.cancelled)); return
            }
            if ContinuousClock.now >= deadline {
                ticket.finish(.failure(CommandSocketError.timedOut)); return
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                ticket.finish(.failure(error)); return
            }
        }
    }
}

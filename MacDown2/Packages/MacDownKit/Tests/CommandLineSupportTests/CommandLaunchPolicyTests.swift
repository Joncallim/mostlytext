import CommandBridge
@testable import CommandLineSupport
import Darwin
import Foundation
import Synchronization
import Testing

struct CommandLaunchPolicyTests {
    @Test func onlyDefiniteAbsenceOrRefusalPermitsColdLaunch() {
        #expect(CommandLineConnection.isAbsent(CommandEndpointError.unavailable(ENOENT)))
        #expect(CommandLineConnection.isAbsent(CommandSocketError.unavailable(ECONNREFUSED)))
        let refused: [any Error] = [
            CommandEndpointError.insecureDirectory, CommandEndpointError.instanceChanged,
            CommandProtocolError.unsupportedVersion, CommandSocketError.timedOut,
            CommandSocketError.cancelled, CommandSocketError.unavailable(EACCES),
        ]
        #expect(refused.allSatisfy { !CommandLineConnection.isAbsent($0) })
    }

    @Test func stalledLaunchTimesOutAndLateCompletionIsIgnored() async throws {
        let saved = Mutex<CommandLaunchWaiter.Ticket?>(nil)
        await #expect(throws: CommandSocketError.timedOut) {
            try await CommandLaunchWaiter.wait(until: .now.advanced(by: .milliseconds(10)), isCancelled: { false },
                                               start: { ticket in saved.withLock { $0 = ticket } })
        }
        let ticket = try #require(saved.withLock { $0 })
        #expect(!ticket.isActive)
        ticket.finish(.success(()))
        ticket.finish(.failure(CommandSocketError.closed))
    }

    @Test func cancellationPreventsLaunchOrEndsAPendingWait() async {
        let starts = Mutex(0)
        await #expect(throws: CommandSocketError.cancelled) {
            try await CommandLaunchWaiter.wait(
                until: .now.advanced(by: .seconds(5)),
                isCancelled: { true },
                start: { _ in
                    starts.withLock { $0 += 1 }
                }
            )
        }
        #expect(starts.withLock { $0 } == 0)
        let cancelled = Mutex(false)
        await #expect(throws: CommandSocketError.cancelled) {
            try await CommandLaunchWaiter.wait(until: .now.advanced(by: .seconds(5)),
                                               isCancelled: { cancelled.withLock { $0 } }, start: { _ in
                                                   cancelled.withLock { $0 = true }
                                               })
        }
    }

    @Test func synchronousAndRepeatedCompletionResumeExactlyOnce() async throws {
        try await CommandLaunchWaiter.wait(
            until: .now.advanced(by: .seconds(5)),
            isCancelled: { false },
            start: { ticket in
                ticket.finish(.success(()))
                ticket.finish(.success(()))
            }
        )
    }

    @Test func structuredTaskCancellationStopsThePendingLaunchWait() async {
        let task = Task {
            try await CommandLaunchWaiter.wait(
                until: .now.advanced(by: .seconds(5)),
                isCancelled: { false },
                start: { _ in }
            )
        }
        task.cancel()
        await #expect(throws: CommandSocketError.cancelled) { try await task.value }
    }
}

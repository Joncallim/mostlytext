@testable import CommandBridge
import Foundation
import Testing

@MainActor
struct CommandApplicationReceiverTests {
    @Test func replayAndCloseBeforeAcceptanceUseTheSameLogicalLifetime() async throws {
        let lifetime = UUID()
        var opens = 0
        let receiver = CommandApplicationReceiver { _, admission in
            opens += 1
            #expect(admission.bind(.path(0), lifetime: lifetime))
            #expect(admission.bind(.path(1), lifetime: lifetime))
            await Task.yield()
        }
        let request = try CommandOpenRequest(paths: ["/one", "/alias"], wait: true)
        let input = try CommandValidatedInput(request: request, bytes: nil)
        let first = CommandReplyMailbox(), second = CommandReplyMailbox()
        try receiver.submit(input, subscriber: UUID(), mailbox: first)
        try receiver.submit(input, subscriber: UUID(), mailbox: second)
        await Task.yield()
        receiver.documentClosed(lifetime)
        try await Self.wait { first.snapshot?.isTerminal == true && second.snapshot?.isTerminal == true }
        #expect(opens == 1)
        let expected: [CommandReceiptEvent] = [
            .accepted(requestID: request.id, openedCount: 1, failures: []),
            .finished(requestID: request.id),
        ]
        #expect(first.snapshot?.events == expected)
        #expect(first.snapshot == second.snapshot)
    }

    @Test func missingTargetsAreFailuresAndDifferentReplayIsRefused() async throws {
        let receiver = CommandApplicationReceiver { _, admission in
            #expect(admission.bind(.path(0), lifetime: UUID()))
            admission.fail(.path(1), reason: .missingFile)
        }
        let request = try CommandOpenRequest(paths: ["/one", "/missing"], wait: false)
        let mailbox = CommandReplyMailbox()
        try receiver.submit(CommandValidatedInput(request: request, bytes: nil), subscriber: UUID(), mailbox: mailbox)
        try await Self.wait { mailbox.snapshot?.isTerminal == true }
        let expected: [CommandReceiptEvent] = [
            .accepted(requestID: request.id, openedCount: 1, failures: [
                CommandOpenFailure(target: .path(1), reason: .missingFile),
            ]),
        ]
        #expect(mailbox.snapshot?.events == expected)
        let changed = try CommandOpenRequest(id: request.id, paths: ["/different"])
        #expect(throws: CommandProtocolError.reusedRequestID) {
            try receiver.submit(CommandValidatedInput(request: changed, bytes: nil),
                                subscriber: UUID(), mailbox: CommandReplyMailbox())
        }
    }

    @Test func disconnectDoesNotCancelAnotherSubscriberAndQuitCompletesOnlyOnConfirmation() async throws {
        let lifetime = UUID()
        var opens = 0
        let receiver = CommandApplicationReceiver { _, admission in
            opens += 1
            #expect(admission.bind(.path(0), lifetime: lifetime))
        }
        let request = try CommandOpenRequest(paths: ["/one"], wait: true)
        let input = try CommandValidatedInput(request: request, bytes: nil)
        let first = CommandReplyMailbox(), second = CommandReplyMailbox()
        let subscriber = UUID()
        try receiver.submit(input, subscriber: subscriber, mailbox: first)
        try receiver.submit(input, subscriber: UUID(), mailbox: second)
        try await Self.wait { first.snapshot?.events.isEmpty == false }
        receiver.disconnect(subscriber)
        #expect(second.snapshot?.isTerminal == false)
        receiver.finishForTermination()
        #expect(second.snapshot?.isTerminal == true)
        #expect(opens == 1)
        #expect(throws: CommandSocketError.closed) {
            try receiver.submit(input, subscriber: UUID(), mailbox: CommandReplyMailbox())
        }
    }

    @Test func rejectedInputNeverBindsAndOmittedTargetsDoNotPretendToOpen() async throws {
        let receiver = CommandApplicationReceiver { _, admission in admission.reject(.recoveryUnavailable) }
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: Data()))
        #expect(throws: CommandProtocolError.invalidStdinDescriptor) {
            try CommandValidatedInput(request: request, bytes: nil)
        }
        let mailbox = CommandReplyMailbox()
        try receiver.submit(CommandValidatedInput(request: request, bytes: Data()),
                            subscriber: UUID(), mailbox: mailbox)
        try await Self.wait { mailbox.snapshot?.isTerminal == true }
        #expect(mailbox.snapshot?.events == [.rejected(requestID: request.id, reason: .recoveryUnavailable)])
    }

    @Test func cancelledQuitReopensAdmissionButConfirmedQuitCannotBeResumed() async throws {
        let receiver = CommandApplicationReceiver { _, admission in
            #expect(admission.bind(.activation, lifetime: UUID()))
        }
        let input = try CommandValidatedInput(request: CommandOpenRequest(paths: []), bytes: nil)
        receiver.suspendAdmission()
        #expect(throws: CommandSocketError.closed) {
            try receiver.submit(input, subscriber: UUID(), mailbox: CommandReplyMailbox())
        }
        receiver.resumeAdmission()
        let mailbox = CommandReplyMailbox()
        try receiver.submit(input, subscriber: UUID(), mailbox: mailbox)
        try await Self.wait { mailbox.snapshot?.isTerminal == true }
        receiver.finishForTermination()
        receiver.resumeAdmission()
        #expect(throws: CommandSocketError.closed) {
            try receiver.submit(input, subscriber: UUID(), mailbox: CommandReplyMailbox())
        }
    }

    private static func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

import CommandBridge
import FileCore
import Foundation
@testable import MacDown2
import Testing

extension SessionViewStateRoundTripTests {
    @Test func commandAliasesShareOneWindowAndSaveAsDoesNotFinishTheWait() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = try coordinatorWithOneTab(sessions: MemorySessionStore(), directory: directory)
        let controller = try #require(coordinator.controllers.first)
        defer { controller.window?.close() }
        try await settleInitialMonitoring(of: coordinator)
        let before = try #require(controller.model.activeDocument)
        let path = try #require(before.fileURL).path
        let lifetime = controller.commandDocumentLifetime
        let receiver = coordinator.makeCommandReceiver()
        let request = try CommandOpenRequest(paths: [path, path], wait: true)
        let mailbox = CommandReplyMailbox()
        try receiver.submit(CommandValidatedInput(request: request, bytes: nil), subscriber: UUID(), mailbox: mailbox)
        try await waitForCommand { mailbox.snapshot?.events.isEmpty == false }
        #expect(coordinator.controllers.count == 1)
        #expect(mailbox.snapshot?.events == [.accepted(requestID: request.id, openedCount: 1, failures: [])])

        let destination = directory.appendingPathComponent("saved-as.md")
        await controller.model.saveAs(to: destination, expecting: before)
        #expect(controller.model.activeDocument?.fileURL == destination)
        #expect(controller.commandDocumentLifetime == lifetime)
        #expect(mailbox.snapshot?.isTerminal == false)

        controller.window?.close()
        #expect(mailbox.snapshot?.isTerminal == true)
        #expect(mailbox.snapshot?.events.last == .finished(requestID: request.id))
    }

    @Test func ordinaryNewFileOpenAdmitsBeforeTheWindowIsPublished() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = try coordinatorWithOneTab(sessions: MemorySessionStore(), directory: directory)
        defer { coordinator.controllers.forEach { $0.window?.close() } }
        let url = directory.appendingPathComponent("second.md")
        try Data("# Second".utf8).write(to: url)
        var admitted = false
        await coordinator.openDocument(at: url, useAmbientWindow: false, admitting: { controller in
            #expect(!controller.isClosed)
            #expect(controller.window?.isVisible == false)
            #expect(!coordinator.controllers.contains(where: { $0 === controller }))
            admitted = true
            return true
        })
        #expect(admitted)
        #expect(coordinator.controllers.count == 2)
    }

    @Test func stdinPersistenceFailureDoesNotOpenAssociatedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        sessions.refusesSaves = true
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        defer { coordinator.controllers.forEach { $0.window?.close() } }
        let url = directory.appendingPathComponent("second.md")
        try Data("# Second".utf8).write(to: url)
        let bytes = Data("source from pipe".utf8)
        let request = try CommandOpenRequest(paths: [url.path], stdin: CommandStdinDescriptor(bytes: bytes), wait: true)
        let mailbox = CommandReplyMailbox()
        try coordinator.makeCommandReceiver().submit(CommandValidatedInput(request: request, bytes: bytes),
                                                     subscriber: UUID(), mailbox: mailbox)
        try await waitForCommand { mailbox.snapshot?.isTerminal == true }
        #expect(coordinator.controllers.count == 1)
        #expect(mailbox.snapshot?.events == [.rejected(requestID: request.id, reason: .recoveryUnavailable)])
    }

    private func waitForCommand(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

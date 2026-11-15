@testable import FileCore
import Foundation
import Testing

struct RecoveryBufferExternalReloadTests {
    @Test func missingRecoveryFileAllowsAnOrdinaryReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        let epoch = try await buffer.mintRecoveryEpoch()

        let outcome = await buffer.removeForExternalReload(for: "document", version: 1, epoch: epoch)

        #expect(outcome.isAbsent)
    }

    @Test func olderCleanupCannotHideANewerRecoveryFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        let epoch = try await buffer.mintRecoveryEpoch()
        #expect(try await buffer.saveCurrentLifetime(content: "newer draft", for: "document", version: 3, epoch: epoch))

        let outcome = await buffer.removeForExternalReload(for: "document", version: 2, epoch: epoch)

        guard case .failed(.verificationFailed) = outcome else {
            Issue.record("Older cleanup incorrectly claimed the newer recovery file was absent: \(outcome)")
            return
        }
        #expect(try await buffer.load(for: "document", epoch: epoch) == "newer draft")
    }
}

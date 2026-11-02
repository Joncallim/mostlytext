import CommandBridge
import FileCore
import Foundation

enum CommandStdinAdmissionFailure: Error, Sendable { case recoveryUnavailable }

/// This factory has no application/window/defaults dependency. All decoding
/// and recovery preparation run away from the UI actor.
enum CommandStdinDocumentFactory {
    static func prepare(_ bytes: Data, recoveryBuffer: RecoveryBuffer) async throws -> FileCore.FileDocument {
        try await Task.detached {
            let payload = try FileByteDecoder.decode(bytes, maximumBytes: CommandProtocol.maximumStdinBytes,
                                                     policy: .explicit(.utf8))
            let created = try await FileCore.FileDocument.create(text: payload.text, encoding: payload.metadata,
                                                                 recoveryBuffer: recoveryBuffer)
            let document = created.edited(text: payload.text)
            guard await document.persistRecovery() else { throw CommandStdinAdmissionFailure.recoveryUnavailable }
            return document
        }.value
    }
}

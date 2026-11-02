import FileCore
import Foundation

public struct InstallationSessionSnapshot: Sendable {
    public let session: WorkspaceSession?
    public let rawDigest: String
}

public extension WorkspaceSessionStore {
    func installationSnapshot() throws -> InstallationSessionSnapshot {
        let before = readForAdmission()
        guard before.admission.permitsPublication else { throw CocoaError(.fileReadCorruptFile) }
        return InstallationSessionSnapshot(session: before.admission.session,
                                           rawDigest: before.bytes.map(Self.digest) ?? "absent")
    }

    /// Recovery relocation can suspend. A newer canonical session owns its
    /// changes, so never recapture it as permission to publish an older plan.
    func publishInstallationSession(_ session: WorkspaceSession, expecting digest: String) -> Bool {
        let before = readForAdmission()
        guard before.admission.permitsPublication,
              (before.bytes.map(Self.digest) ?? "absent") == digest,
              let baseline = before.baseline,
              let bytes = try? JSONEncoder().encode(session),
              case .readable = WorkspaceSessionAdmission.decode(bytes),
              let text = String(data: bytes, encoding: .utf8) else { return false }
        do {
            try beforePublication?(fileURL)
            try FileStore().write(text, to: fileURL, destinationBaseline: baseline)
            return readForAdmission().bytes == bytes
        } catch { return false }
    }
}

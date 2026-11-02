import Darwin
import FileCore
import Foundation

extension WorkspaceSessionStore {
    @discardableResult
    public func saveSessionVerified(_ session: WorkspaceSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session),
              case .readable = WorkspaceSessionAdmission.decode(data),
              let text = String(data: data, encoding: .utf8) else { return false }
        let before = readForAdmission()
        guard before.admission.permitsPublication, let baseline = before.baseline else {
            if let raw = before.bytes {
                preserveUnreadableSession(raw)
            }
            return false
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try beforePublication?(fileURL)
            try FileStore().write(text, to: fileURL, destinationBaseline: baseline)
            let after = readForAdmission()
            return after.admission.permitsPublication && after.bytes == data
        } catch { return false }
    }

    /// A backup is supplementary evidence, never permission to replace the
    /// unsupported primary. Keep the first copy and create it privately.
    func preserveUnreadableSession(_ bytes: Data) {
        let backup = fileURL.appendingPathExtension("unreadable")
        let descriptor = open(backup.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    return
                }
                guard count > 0 else { return }
                offset += count
            }
            _ = fsync(descriptor)
        }
    }
}

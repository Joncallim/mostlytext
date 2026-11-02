import CryptoKit
import Darwin
import FileCore
import Foundation

extension WorkspaceSessionStore {
    struct AdmissionSnapshot {
        let admission: WorkspaceSessionAdmission
        let bytes: Data?
        let baseline: DestinationBaseline?
    }

    public func inspectSession() -> WorkspaceSessionAdmission {
        readForAdmission().admission
    }

    func readForAdmission() -> AdmissionSnapshot {
        do {
            return try readOwnedSnapshot()
        } catch {
            return AdmissionSnapshot(admission: .unreadable, bytes: nil, baseline: nil)
        }
    }

    private func readOwnedSnapshot() throws -> AdmissionSnapshot {
        let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return AdmissionSnapshot(admission: .absent, bytes: nil, baseline: .absent)
            }
            throw CocoaError(.fileReadUnknown)
        }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1 else { throw CocoaError(.fileReadUnknown) }
        guard before.st_size <= WorkspaceSessionAdmission.maximumBytes else {
            return AdmissionSnapshot(admission: .tooLarge, bytes: nil, baseline: nil)
        }
        let bytes = try boundedRead(descriptor)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        var after = stat()
        var named = stat()
        guard fstat(descriptor, &after) == 0, lstat(fileURL.path, &named) == 0,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              before.st_size == after.st_size, after.st_size == bytes.count,
              named.st_dev == after.st_dev, named.st_ino == after.st_ino,
              (attributes[.systemNumber] as? NSNumber)?.stringValue == String(after.st_dev),
              (attributes[.systemFileNumber] as? NSNumber)?.stringValue == String(after.st_ino) else {
            throw CocoaError(.fileReadUnknown)
        }
        let revision = FileRevision(url: fileURL.standardizedFileURL,
                                    modificationDate: attributes[.modificationDate] as? Date,
                                    fileSize: bytes.count,
                                    fileObjectID: .init(volume: String(after.st_dev), file: String(after.st_ino)),
                                    sha256: Self.digest(bytes))
        return AdmissionSnapshot(admission: .decode(bytes), bytes: bytes, baseline: .revision(revision))
    }

    private func boundedRead(_ descriptor: Int32) throws -> Data {
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 {
                return bytes
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw CocoaError(.fileReadUnknown)
            }
            guard count <= WorkspaceSessionAdmission.maximumBytes - bytes.count else {
                throw CocoaError(.fileReadTooLarge)
            }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

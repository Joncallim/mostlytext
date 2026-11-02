import Darwin
import Foundation

extension InstallationTree {
    func info(_ descriptor: Int32, kind: mode_t) throws -> InstallationFileIdentity {
        var raw = stat()
        guard fstat(descriptor, &raw) == 0, raw.st_mode & 0o022 == 0 else { throw LegacyMigrationFailure.unsafeStorage }
        try storage.validate(descriptor, kind: kind, mode: raw.st_mode & 0o7777)
        return InstallationFileIdentity(raw)
    }

    func read(_ descriptor: Int32) throws -> Data {
        let before = try info(descriptor, kind: S_IFREG)
        guard before.size >= 0,
              before.size <= Self.maximumFileBytes else { throw LegacyPreferenceSnapshotError.tooLarge }
        var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 {
                break
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw LegacyMigrationFailure.unavailable(errno)
            }
            guard count <= Self.maximumFileBytes - bytes.count else { throw LegacyPreferenceSnapshotError.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        guard bytes.count == before.size, try info(descriptor, kind: S_IFREG) == before else {
            throw LegacyMigrationFailure.changedStorage
        }
        return bytes
    }

    func names(_ descriptor: Int32) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        guard let directory = fdopendir(duplicate)
        else { Darwin.close(duplicate); throw LegacyMigrationFailure.unavailable(errno) }
        defer { closedir(directory) }
        rewinddir(directory)
        var result: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let bytes = withUnsafeBytes(of: entry.pointee.d_name) { Data($0.prefix { $0 != 0 }) }
            guard let name = String(data: bytes, encoding: .utf8) else { throw LegacyMigrationFailure.unsafeStorage }
            if name != ".", name != ".." {
                result.append(name)
            }
            guard result.count <= Self.maximumEntries else { throw LegacyPreferenceSnapshotError.tooManyEntries }
            errno = 0
        }
        guard errno == 0 else { throw LegacyMigrationFailure.unavailable(errno) }
        return result.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    func components(_ path: String) throws -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= 9,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0) })
        else { throw LegacyMigrationFailure.invalidRecord }
        return parts
    }

    func last(_ parts: [String]) throws -> String {
        guard let last = parts.last else { throw LegacyMigrationFailure.invalidRecord }
        return last
    }
}
